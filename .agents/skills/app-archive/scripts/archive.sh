#!/bin/zsh
set -euo pipefail

skill_dir="${0:A:h:h}"
config_path="$skill_dir/config.env"
fail() { print -u2 -r -- "$1"; exit "${2:-65}"; }
usage() {
  cat <<'HELP'
Usage: archive.sh [options]
  --config FILE                 Trusted local shell config (default: ../config.env)
  --marketing-version VERSION   MARKETING_VERSION override, not persisted
  --build-number BUILD          Override automatic yyyyMMddNN build, not persisted
  --output-root DIR             Override output root (relative to project)
  --archive-path PATH           Override xcarchive path; must not exist
  --export-dir DIR              Override IPA directory; must not exist
  --derived-data-path DIR        Override DerivedData path
  --build-setting KEY=VALUE      Additional build setting; repeatable
  --archive-only                Do not export an IPA
  --skip-macro-validation       Only with explicit authorization for this run
  --dry-run                     Read-only preflight and command preview
  -h, --help                    Show this help
HELP
}
# Parse before sourcing config so help and malformed arguments have no build effects.
typeset -A archive_options
archive_options=()
typeset -a extra_settings
extra_settings=()
archive_only=false
dry_run=false
skip_macros=false
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --archive-only) archive_only=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --skip-macro-validation) skip_macros=true; shift ;;
    --config|--marketing-version|--build-number|--output-root|--archive-path|--export-dir|--derived-data-path|--build-setting)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value" 64
      if [[ "$1" == --build-setting ]]; then
        [[ "$2" =~ '^[A-Za-z_][A-Za-z0-9_]*(\[[^]]+\])?=.*$' ]] || fail 'Expected KEY=VALUE for --build-setting' 64
        extra_settings+=("$2")
      else
        archive_options[$1]="$2"
      fi
      shift 2 ;;
    *) fail "Unknown argument: $1 (see --help)" 64 ;;
  esac
done
config_path="${archive_options[--config]:-$config_path}"
config_path="${config_path:A}"
[[ -f "$config_path" ]] || fail "Config not found: $config_path" 66
source "$config_path"
absolute_path() {
  local base_path="$1" input_path="$2"
  [[ "$input_path" == /* ]] || input_path="$base_path/$input_path"
  print -r -- "${input_path:A}"
}
root="$(absolute_path "${config_path:h}" "${PROJECT_ROOT:?}")"
project="$(absolute_path "$root" "${PROJECT:?}")"
scheme="${SCHEME:?}"
configuration="${CONFIGURATION:?}"
export_method="${EXPORT_METHOD:?}"
team_id="${TEAM_ID:?}"
expected_id="${EXPECTED_BUNDLE_IDENTIFIER:?}"
[[ "${ALLOW_PROVISIONING_UPDATES:-false}" == (true|false) ]] || fail 'Invalid ALLOW_PROVISIONING_UPDATES'
[[ -f "$project/project.pbxproj" ]] || fail "Project not found: $project" 66
[[ -f "$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]] || fail 'Project Package.resolved not found.' 66
source_packages="$(absolute_path "$root" "${SOURCE_PACKAGES_PATH:?}")"

output_root="$(absolute_path "$root" "${archive_options[--output-root]:-${OUTPUT_ROOT:?}}")"
safe_scheme="${scheme//[^A-Za-z0-9._-]/-}"
run_dir="$output_root/$safe_scheme-$(/bin/date +%Y%m%d-%H%M%S)-$$"
archive_path="$(absolute_path "$root" "${archive_options[--archive-path]:-$run_dir/$safe_scheme.xcarchive}")"
export_dir="$(absolute_path "$root" "${archive_options[--export-dir]:-$run_dir/ipa}")"
derived_data="$(absolute_path "$root" "${archive_options[--derived-data-path]:-${DERIVED_DATA_PATH:?}}")"
[[ ! -e "$archive_path" && ! -L "$archive_path" ]] || fail "Archive path already exists: $archive_path" 73
if [[ "$archive_only" == false ]]; then
  [[ ! -e "$export_dir" && ! -L "$export_dir" ]] || fail "Export path already exists: $export_dir" 73
fi

# Reserve numbers in the project, independent of the chosen output directory.
# Atomic mkdir prevents concurrent builds from selecting the same number.
build_number="${archive_options[--build-number]:-}"
if [[ -z "$build_number" ]]; then
  build_day="$(TZ=Asia/Shanghai /bin/date +%Y%m%d)"
  number_root="$root/build/archive-build-numbers"
  highest=0
  typeset -a prior_infos
  prior_infos=("$root"/build/releases/**/*.xcarchive/Info.plist(N) "$output_root"/**/*.xcarchive/Info.plist(N))
  for prior_info in "${prior_infos[@]}"; do
    prior_build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$prior_info" 2>/dev/null || true)"
    if [[ "$prior_build" == ${build_day}[0-9][0-9] ]]; then
      prior_number=$(( 10#${prior_build[-2,-1]} ))
      (( prior_number <= highest )) || highest=$prior_number
    fi
  done
  if [[ "$dry_run" == false ]]; then mkdir -p "$number_root"; fi
  while true; do
    (( highest += 1 ))
    (( highest <= 99 )) || fail "Daily build numbers exhausted for $build_day"
    printf -v build_number '%s%02d' "$build_day" "$highest"
    [[ ! -e "$number_root/$build_number" ]] || continue
    [[ "$dry_run" == false ]] || break
    if /bin/mkdir "$number_root/$build_number" 2>/dev/null; then break; fi
    [[ -d "$number_root/$build_number" ]] || fail "Cannot reserve build number: $build_number"
  done
fi
for setting in "${extra_settings[@]}"; do
  [[ "$setting" != CURRENT_PROJECT_VERSION=* ]] || fail 'Use --build-number instead of --build-setting CURRENT_PROJECT_VERSION' 64
done

typeset -a archive_args export_args
archive_args=(archive -project "$project" -scheme "$scheme" -configuration "$configuration"
  -destination 'generic/platform=iOS' -archivePath "$archive_path" -derivedDataPath "$derived_data"
  -clonedSourcePackagesDirPath "$source_packages" -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile "DEVELOPMENT_TEAM=$team_id")
[[ -z "${archive_options[--marketing-version]:-}" ]] || archive_args+=("MARKETING_VERSION=${archive_options[--marketing-version]}")
archive_args+=("CURRENT_PROJECT_VERSION=$build_number")
archive_args+=("${extra_settings[@]}")
[[ "$skip_macros" == false ]] || archive_args+=(-skipMacroValidation)
export_args=(-exportArchive -archivePath "$archive_path" -exportPath "$export_dir" -exportOptionsPlist "$run_dir/ExportOptions.plist")
if [[ "${ALLOW_PROVISIONING_UPDATES:-false}" == true ]]; then
  archive_args+=(-allowProvisioningUpdates)
  export_args+=(-allowProvisioningUpdates)
fi
if [[ "$dry_run" == true ]]; then
  print -rl -- "CONFIG=$config_path" "OUTPUT=$run_dir" "EXPORT_METHOD=$export_method" "EXPECTED_BUNDLE_ID=$expected_id"
  print -r -- "/usr/bin/xcodebuild ${(j: :)${(@q)archive_args}}"
  [[ "$archive_only" == true ]] || print -r -- "/usr/bin/xcodebuild ${(j: :)${(@q)export_args}}"
  exit 0
fi
mkdir -p "$run_dir" "${archive_path:h}"
cd "$root"
print -r -- "APP_LOG_DIR=$run_dir"
/usr/bin/xcodebuild "${archive_args[@]}" 2>&1 | /usr/bin/tee "$run_dir/archive.log"
archive_info="$archive_path/Info.plist"
[[ -f "$archive_info" ]] || fail "Archive metadata missing: $archive_info"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
bundle_id="$(read_plist "$archive_info" ApplicationProperties:CFBundleIdentifier)"
version="$(read_plist "$archive_info" ApplicationProperties:CFBundleShortVersionString)"
build="$(read_plist "$archive_info" ApplicationProperties:CFBundleVersion)"
[[ "$bundle_id" == "$expected_id" ]] || fail "Archive bundle identifier mismatch: $bundle_id"
[[ -z "${archive_options[--marketing-version]:-}" || "$version" == "${archive_options[--marketing-version]}" ]] || fail "Archive version mismatch: $version"
[[ "$build" == "$build_number" ]] || fail "Archive build mismatch: $build"

if [[ "$archive_only" == false ]]; then
  export_options="$run_dir/ExportOptions.plist"
  /usr/bin/plutil -create xml1 "$export_options"
  /usr/bin/plutil -insert method -string "$export_method" "$export_options"
  /usr/bin/plutil -insert destination -string export "$export_options"
  /usr/bin/plutil -insert signingStyle -string automatic "$export_options"
  /usr/bin/plutil -insert teamID -string "$team_id" "$export_options"
  /usr/bin/plutil -insert stripSwiftSymbols -bool YES "$export_options"
  /usr/bin/plutil -insert thinning -string '<none>' "$export_options"
  /usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool NO "$export_options"
  /usr/bin/xcodebuild "${export_args[@]}" 2>&1 | /usr/bin/tee "$run_dir/export.log"
  typeset -a ipa_files info_entries
  ipa_files=("$export_dir"/*.ipa(N))
  (( ${#ipa_files} == 1 )) || fail "Expected exactly one IPA in $export_dir, found ${#ipa_files}"
  /usr/bin/unzip -tq "$ipa_files[1]"
  info_entries=("${(@f)$(/usr/bin/unzip -Z1 "$ipa_files[1]" | /usr/bin/awk -F/ 'NF == 3 && $1 == "Payload" && $2 ~ /\.app$/ && $3 == "Info.plist"')}")
  (( ${#info_entries} == 1 )) && [[ -n "$info_entries[1]" ]] || fail 'Expected one main app Info.plist in IPA'
  /usr/bin/unzip -p "$ipa_files[1]" "$info_entries[1]" > "$run_dir/IPA-Info.plist"
  [[ "$(read_plist "$run_dir/IPA-Info.plist" CFBundleIdentifier)" == "$bundle_id" ]] || fail 'IPA bundle identifier mismatch'
  [[ "$(read_plist "$run_dir/IPA-Info.plist" CFBundleShortVersionString)" == "$version" ]] || fail 'IPA version mismatch'
  [[ "$(read_plist "$run_dir/IPA-Info.plist" CFBundleVersion)" == "$build" ]] || fail 'IPA build mismatch'
  print -r -- "APP_IPA_PATH=$ipa_files[1]"
fi
print -rl -- "APP_BUNDLE_ID=$bundle_id" "APP_VERSION=$version" "APP_BUILD=$build" "APP_ARCHIVE_PATH=$archive_path"
