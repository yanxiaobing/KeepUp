#!/bin/zsh
set -euo pipefail
skill_dir="${0:A:h:h}"
config_path="$skill_dir/config.env"
artifact=""; changelog=""; changelog_mode=unset; short_override=""; package_url=""
inspect_only=false; notify_only=false
fail() { print -u2 -r -- "$1"; exit "${2:-65}"; }
while (( $# )); do
  case "$1" in
    -h|--help)
      cat <<'HELP'
Usage: publish.sh --artifact FILE (--changelog TEXT | --no-changelog) [options]
  --inspect-only               Offline IPA metadata inspection; no credentials needed
  --notify-only --package-url URL  Notify an already confirmed release, without uploading
  --short CODE                 Override configured fir short code
  --config FILE                Trusted local config (credentials.env beside it)
HELP
      exit 0 ;;
    --inspect-only) inspect_only=true; shift ;;
    --notify-only) notify_only=true; shift ;;
    --no-changelog) [[ "$changelog_mode" == unset ]] || fail 'Choose one changelog mode' 64; changelog_mode=none; shift ;;
    --config|--artifact|--changelog|--short|--package-url)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value" 64
      case "$1" in
        --config) config_path="$2" ;;
        --artifact) artifact="$2" ;;
        --changelog) [[ "$changelog_mode" == unset ]] || fail 'Choose one changelog mode' 64; changelog="$2"; changelog_mode=value ;;
        --short) short_override="$2" ;;
        --package-url) package_url="$2" ;;
      esac
      shift 2 ;;
    *) fail "Unknown argument: $1" 64 ;;
  esac
done
config_path="${config_path:A}"
[[ -f "$config_path" ]] || fail "Config not found: $config_path" 66
source "$config_path"
root="${config_path:h}/${PROJECT_ROOT:?}"; root="${root:A}"
[[ -n "$artifact" ]] || fail '--artifact is required' 64
[[ "$artifact" == /* ]] || artifact="$root/$artifact"
artifact="${artifact:A}"
[[ -f "$artifact" && "${artifact:l}" == *.ipa ]] || fail "Existing IPA required: $artifact" 66
fir_bin="${FIR_BIN:-fir}"
[[ "$fir_bin" == */* ]] || fir_bin="$(command -v "$fir_bin" || true)"
[[ -n "$fir_bin" && -x "$fir_bin" ]] || fail 'fir-cli not found' 69
ruby_bin="$(command -v ruby || true)"
[[ -n "$ruby_bin" ]] || fail 'Ruby not found' 69
# info reads the IPA locally; it does not need the publishing token.
info_output="$("$fir_bin" info "$artifact" 2>/dev/null)" || fail 'fir info failed; verify the IPA locally.'
field() { print -r -- "$info_output" | /usr/bin/awk -v key="$1" 'index($0, key ":") {sub("^.*" key ":[[:space:]]*", ""); print; exit}'; }
bundle_id="$(field identifier)"; app_name="$(field display_name)"; version="$(field version)"; build="$(field build)"
[[ "$bundle_id" == "${EXPECTED_BUNDLE_IDENTIFIER:?}" ]] || fail "Bundle identifier mismatch: $bundle_id"
[[ -n "$version" && -n "$build" && -n "$app_name" ]] || fail 'Incomplete IPA metadata'
print -rl -- "APP_BUNDLE_ID=$bundle_id" "APP_NAME=$app_name" "APP_VERSION=$version" "APP_BUILD=$build"
[[ "$inspect_only" == false ]] || exit 0
[[ "$changelog_mode" != unset ]] || fail 'Pass --changelog or explicitly --no-changelog' 64
[[ "$changelog_mode" != value || -n "${changelog//[[:space:]]/}" ]] || fail '--changelog cannot be blank' 64
[[ "$notify_only" == true || -z "$package_url" ]] || fail '--package-url requires --notify-only' 64
if [[ -f "${config_path:h}/credentials.env" ]]; then source "${config_path:h}/credentials.env"; fi
webhook="${FIR_LARK_WEBHOOK_URL:-}"
[[ "$webhook" =~ '^https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9_-]+$' ]] || fail 'Configure the full FIR_LARK_WEBHOOK_URL in credentials.env' 77
[[ "$notify_only" == true || -n "${FIR_API_TOKEN:-}" ]] || fail 'Configure FIR_API_TOKEN in credentials.env' 77
valid_package_url() { [[ "$package_url" =~ '^https?://[^[:space:]]+[?&]release_id=[A-Za-z0-9_-]+' ]]; }
[[ "$notify_only" == false ]] || valid_package_url || fail 'A confirmed release-specific --package-url is required' 64
output_root="${OUTPUT_ROOT:?}"
[[ "$output_root" == /* ]] || output_root="$root/$output_root"
umask 077
mkdir -p "$output_root"
run_dir="$(/usr/bin/mktemp -d "$output_root/publish-$(/bin/date +%Y%m%d-%H%M%S).XXXXXX")"
print -r -- "FIR_LOG_DIR=$run_dir"
if [[ "$notify_only" == false ]]; then
  typeset -a publish_args
  publish_args=(publish "$artifact" --need-release-id --skip-fir-cli-feedback)
  [[ "$changelog_mode" != value ]] || publish_args+=(--changelog "$changelog")
  short_code="${short_override:-${FIR_SHORT:-}}"
  [[ -z "$short_code" ]] || publish_args+=(--short "$short_code")
  # Do not print raw CLI output: it may contain temporary upload credentials.
  API_TOKEN="$FIR_API_TOKEN" API_YML_PATH="$skill_dir/api.yml" \
    "$ruby_bin" "$skill_dir/scripts/fir_cli.rb" "$fir_bin" "${publish_args[@]}" > "$run_dir/publish.log" 2>&1 || fail "fir upload failed or result uncertain; inspect private log before retry: $run_dir/publish.log" 1
  package_url="$(/usr/bin/awk '/Published succeed:/ {sub(/^.*Published succeed:[[:space:]]*/, ""); print; exit}' "$run_dir/publish.log")"
  valid_package_url || fail 'Upload returned no confirmed release-specific URL; check fir before any retry.'
  print -r -- 'FIR_UPLOAD_SUCCEEDED=true'
fi
print -r -- "PACKAGE_URL=$package_url"
# Preserve the URL before notification, so a notification failure never requires another upload.
print -r -- "$package_url" > "$run_dir/package-url.txt"
notification_payload="$("$ruby_bin" -rjson -e '
  name, version, build, url, mode, notes = ARGV
  lines = notes.lines.map(&:strip).reject(&:empty?)
  changes = mode == "none" ? "无" : lines.each_with_index.map { |s,i| "#{i+1}. #{s}" }.join("\n")
  text = "#{name} #{version} (Build #{build})\n\n下载地址:\n\n#{url}\n\n相对上次测试包变更：\n\n#{changes}"
  print JSON.generate(msg_type: "text", content: {text: text})
' "$app_name" "$version" "$build" "$package_url" "$changelog_mode" "$changelog")"
# URL is passed through stdin, not command-line arguments or console output.
print -r -- "url = \"$webhook\"" | /usr/bin/curl -fsS --connect-timeout 10 --max-time 30 \
  --config - --request POST --header 'Content-Type: application/json' --data-binary "$notification_payload" \
  > "$run_dir/notification-response.json" 2> "$run_dir/notification-error.log" || fail "Lark request failed; upload URL remains valid: $package_url" 75
"$ruby_bin" -rjson -e '
  r = JSON.parse(File.read(ARGV[0]))
  exit 1 unless r.is_a?(Hash)
  code = r.key?("code") ? r["code"] : r["StatusCode"]
  exit([0, "0"].include?(code) ? 0 : 1)
' "$run_dir/notification-response.json" 2>/dev/null || fail "Lark response rejected or malformed; upload URL remains valid: $package_url" 75
print -r -- 'LARK_NOTIFICATION_SUCCEEDED=true'
