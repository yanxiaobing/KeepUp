#!/bin/zsh
set -euo pipefail
skill_dir="${0:A:h:h}"
config_path="$skill_dir/config.env"
archive_path=""
inspect_only=false
fail() { print -u2 -r -- "$1"; exit "${2:-65}"; }
while (( $# )); do
  case "$1" in
    -h|--help) print -r -- 'Usage: publish.sh --archive PATH [--config FILE] [--inspect-only]'; exit 0 ;;
    --inspect-only) inspect_only=true; shift ;;
    --archive|--config)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value" 64
      if [[ "$1" == --archive ]]; then archive_path="$2"; else config_path="$2"; fi
      shift 2 ;;
    *) fail "Unknown argument: $1" 64 ;;
  esac
done
config_path="${config_path:A}"
[[ -f "$config_path" ]] || fail "Config not found: $config_path" 66
source "$config_path"
root="${config_path:h}/${PROJECT_ROOT:?}"
root="${root:A}"
[[ "${EXPORT_METHOD:?}" == app-store-connect ]] || fail 'Store export method must be app-store-connect'
[[ "${ALLOW_PROVISIONING_UPDATES:-false}" == (true|false) && "${UPLOAD_SYMBOLS:-true}" == (true|false) ]] || fail 'Invalid boolean configuration'
[[ -n "$archive_path" ]] || fail '--archive is required' 64
[[ "$archive_path" == /* ]] || archive_path="$root/$archive_path"
archive_path="${archive_path:A}"
[[ -d "$archive_path" && "$archive_path" == *.xcarchive ]] || fail "Archive not found: $archive_path" 66
info="$archive_path/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "$info"; }
bundle_id="$(read_plist CFBundleIdentifier)"
version="$(read_plist CFBundleShortVersionString)"
build="$(read_plist CFBundleVersion)"
[[ "$bundle_id" == "${EXPECTED_BUNDLE_IDENTIFIER:?}" ]] || fail "Bundle identifier mismatch: $bundle_id"
[[ -n "$version" && -n "$build" ]] || fail 'Missing archive version or build'
print -rl -- "APP_BUNDLE_ID=$bundle_id" "APP_VERSION=$version" "APP_BUILD=$build" "APP_ARCHIVE_PATH=$archive_path"
[[ "$inspect_only" == false ]] || exit 0
output_root="${OUTPUT_ROOT:?}"
[[ "$output_root" == /* ]] || output_root="$root/$output_root"
mkdir -p "$output_root"
run_dir="$(/usr/bin/mktemp -d "$output_root/upload-$(/bin/date +%Y%m%d-%H%M%S).XXXXXX")"
export_options="$run_dir/ExportOptions.plist"
/usr/bin/plutil -create xml1 "$export_options"
/usr/bin/plutil -insert destination -string upload "$export_options"
/usr/bin/plutil -insert method -string "$EXPORT_METHOD" "$export_options"
/usr/bin/plutil -insert teamID -string "${TEAM_ID:?}" "$export_options"
/usr/bin/plutil -insert signingStyle -string automatic "$export_options"
/usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool NO "$export_options"
/usr/bin/plutil -insert stripSwiftSymbols -bool YES "$export_options"
/usr/bin/plutil -insert uploadSymbols -bool "${UPLOAD_SYMBOLS:-true}" "$export_options"
typeset -a upload_args
upload_args=(-exportArchive -archivePath "$archive_path" -exportPath "$run_dir/export" -exportOptionsPlist "$export_options")
[[ "${ALLOW_PROVISIONING_UPDATES:-false}" == false ]] || upload_args+=(-allowProvisioningUpdates)
print -r -- "STORE_LOG_DIR=$run_dir"
cd "$root"
/usr/bin/xcodebuild "${upload_args[@]}" 2>&1 | /usr/bin/tee "$run_dir/upload.log"
print -r -- 'STORE_UPLOAD_SUCCEEDED=true'
