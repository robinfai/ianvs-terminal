#!/usr/bin/env bash
# Build the isolated mobile PRD fixture. Never installs or starts an application.
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
BUNDLE_ID='work.ianvs.trail.mobileprd'
TARGET='integration_test/mobile_prd_acceptance_test.dart'
BUILD_PLATFORM=''
BUILD_MODE=''
FIXTURE_FILE=''
SIGNING_TEAM=''
SIGNING_PROFILE=''
FLUTTER_COMMAND="${FLUTTER:-flutter}"
XCODE_COMMAND="${XCODEBUILD:-xcodebuild}"
CODESIGN_COMMAND="${CODESIGN:-codesign}"
PYTHON_COMMAND="${PYTHON:-python3}"

usage() {
  cat <<'USAGE'
Usage: build_ios_fixture.sh --platform simulator|physical --mode debug|profile|release
       --fixture /path/to/defines.json [--team TEAM_ID --profile PROFILE_UUID]

Simulator supports debug only. Physical builds require an explicitly supplied
team and an already installed provisioning profile UUID; no account discovery,
provisioning updates, device registration, installation or simulator fallback.
The fixture must contain TRAIL_MOBILE_PRD_FIXTURE as a JSON string with runId,
ssh, modelBaseUrl and evidenceBaseUrl. TRAIL_MOBILE_PRD_CASE is optional.
FLUTTER, XCODEBUILD, CODESIGN and PYTHON may select existing tool executables.
Build products and private logs are written under build/mobile-prd-v1.1/ios.
Do not publish raw build logs: Xcode may include encoded fixture definitions.
USAGE
}

fail_usage() { printf '%s\n' "$1" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--mode|--fixture|--team|--profile)
      [[ $# -ge 2 && -n "$2" ]] || fail_usage 'An option value is missing.'
      case "$1" in
        --platform) BUILD_PLATFORM="$2" ;;
        --mode) BUILD_MODE="$2" ;;
        --fixture) FIXTURE_FILE="$2" ;;
        --team) SIGNING_TEAM="$2" ;;
        --profile) SIGNING_PROFILE="$2" ;;
      esac
      shift 2 ;;
    *) fail_usage 'Unknown option; see --help.' ;;
  esac
done

case "$BUILD_PLATFORM" in simulator|physical) ;; *) fail_usage 'Choose simulator or physical explicitly.' ;; esac
case "$BUILD_MODE" in debug|profile|release) ;; *) fail_usage 'Choose debug, profile or release explicitly.' ;; esac
if [[ "$BUILD_PLATFORM" == simulator ]]; then
  [[ "$BUILD_MODE" == debug ]] || fail_usage 'Flutter supports iOS simulator builds only in debug mode; no fallback was attempted.'
  [[ -z "$SIGNING_TEAM" && -z "$SIGNING_PROFILE" ]] || fail_usage 'Simulator builds do not accept signing account parameters.'
else
  [[ "$SIGNING_TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail_usage 'Physical builds require an explicit 10-character Team ID.'
  [[ "$SIGNING_PROFILE" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] || fail_usage 'Physical builds require an explicit existing provisioning profile UUID.'
fi
[[ -n "$FIXTURE_FILE" && -f "$FIXTURE_FILE" ]] || fail_usage 'A fixture definition file is required.'
[[ -f "$EXAMPLE_DIR/$TARGET" ]] || fail_usage 'The dedicated mobile PRD entrypoint is missing.'
for tool in "$FLUTTER_COMMAND" "$XCODE_COMMAND" "$PYTHON_COMMAND"; do
  command -v "$tool" >/dev/null 2>&1 || fail_usage 'A required build tool is unavailable.'
done
if [[ "$BUILD_PLATFORM" == physical ]]; then
  command -v "$CODESIGN_COMMAND" >/dev/null 2>&1 || fail_usage 'codesign is required for physical builds.'
fi

TEMP_BASE="$ROOT_DIR/build/tmp/mobile-prd-ios"
OUTPUT_BASE="$ROOT_DIR/build/mobile-prd-v1.1/ios"
mkdir -p "$TEMP_BASE" "$OUTPUT_BASE"
BUILD_LOCK="$TEMP_BASE/build.lock"
mkdir "$BUILD_LOCK" 2>/dev/null || fail_usage 'Another fixture build owns the temporary build lock; no build was started.'
SIGNING_ROOT=''
OUTPUT_DIR=''
GENERATED_BACKUP_READY=0
BUILD_SUCCEEDED=0
cleanup() {
  local build_exit=$?
  trap - EXIT
  if [[ "$GENERATED_BACKUP_READY" == 1 ]]; then
    if ! "$PYTHON_COMMAND" - "$EXAMPLE_DIR" "$SIGNING_ROOT/backup" <<'PY'
import json, pathlib, shutil, sys
root, backup = map(pathlib.Path, sys.argv[1:])
for item in json.loads((backup / 'index.json').read_text()):
    target = root / item['path']
    if item['existed']:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(backup / item['copy'], target)
    elif target.exists():
        target.unlink()
PY
    then
      printf '%s\n' 'Could not restore generated Flutter configuration; keep this checkout idle until reviewed.' >&2
      build_exit=1
    fi
  fi
  if [[ "$BUILD_SUCCEEDED" != 1 && -n "$OUTPUT_DIR" ]]; then
    # This directory was created by this invocation, never a previous build.
    rm -rf -- "$OUTPUT_DIR/Products"
  fi
  if [[ -n "$SIGNING_ROOT" ]]; then rm -rf -- "$SIGNING_ROOT"; fi
  rmdir "$BUILD_LOCK" 2>/dev/null || true
  exit "$build_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SIGNING_ROOT="$(mktemp -d "$TEMP_BASE/run.XXXXXX")"

# Snapshot only the supplied disposable fixture. Never inspect saved app data,
# secure storage, account credentials or a user SSH configuration.
"$PYTHON_COMMAND" - "$FIXTURE_FILE" "$SIGNING_ROOT/fixture.json" <<'PY'
import json, pathlib, sys
try:
    source = pathlib.Path(sys.argv[1]).read_bytes()
    definitions = json.loads(source)
    if not isinstance(definitions, dict):
        raise ValueError()
    encoded = definitions.get('TRAIL_MOBILE_PRD_FIXTURE')
    if not isinstance(encoded, str):
        raise ValueError()
    fixture = json.loads(encoded)
    if not isinstance(fixture, dict) or not isinstance(fixture.get('ssh'), dict):
        raise ValueError()
    if any(not isinstance(fixture.get(key), str) or not fixture[key].strip()
           for key in ('runId', 'modelBaseUrl', 'evidenceBaseUrl')):
        raise ValueError()
    if 'TRAIL_MOBILE_PRD_CASE' in definitions and not isinstance(definitions['TRAIL_MOBILE_PRD_CASE'], str):
        raise ValueError()
    pathlib.Path(sys.argv[2]).write_bytes(source)
except (OSError, ValueError, TypeError):
    print('Invalid fixture JSON or missing mobile PRD keys; contents were not printed.', file=sys.stderr)
    sys.exit(64)
PY

OUTPUT_DIR="$(mktemp -d "$OUTPUT_BASE/$BUILD_PLATFORM-$BUILD_MODE.XXXXXX")"
PRIVATE_LOG="$OUTPUT_DIR/build.private.log"
SIGNING_CONFIG="$SIGNING_ROOT/Acceptance.xcconfig"
SIGNING_ENTITLEMENTS="$SIGNING_ROOT/Acceptance.entitlements"
cat >"$SIGNING_ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>keychain-access-groups</key>
  <array><string>$(AppIdentifierPrefix)work.ianvs.trail.mobileprd</string></array>
</dict></plist>
PLIST
"$PYTHON_COMMAND" - "$SIGNING_CONFIG" "$SIGNING_ENTITLEMENTS" "$BUILD_PLATFORM" "$SIGNING_TEAM" "$SIGNING_PROFILE" <<'PY'
import pathlib, sys
config, entitlements, platform, team, profile = sys.argv[1:]
# The value is a generated local path; reject xcconfig delimiters instead of
# accidentally turning a path into an extra build setting.
if any(c in entitlements for c in ('\n', '\r', '"', '$')):
    sys.exit('The checkout path cannot be represented safely in xcconfig.')
settings = [
    'PRODUCT_BUNDLE_IDENTIFIER = work.ianvs.trail.mobileprd',
    f'CODE_SIGN_ENTITLEMENTS = "{entitlements}"',
    'CODE_SIGNING_ALLOWED = ' + ('YES' if platform == 'physical' else 'NO'),
]
if platform == 'physical':
    settings += ['CODE_SIGN_STYLE = Manual', 'CODE_SIGN_IDENTITY = Apple Development',
                 f'DEVELOPMENT_TEAM = {team}', f'PROVISIONING_PROFILE_SPECIFIER = {profile}']
pathlib.Path(config).write_text('\n'.join(settings) + '\n')
PY

# Flutter writes encoded Dart defines to these generated files even with
# --config-only. Restore their original bytes/modes on success and every failure.
"$PYTHON_COMMAND" - "$EXAMPLE_DIR" "$SIGNING_ROOT/backup" <<'PY'
import json, pathlib, shutil, sys
root, backup = map(pathlib.Path, sys.argv[1:])
backup.mkdir()
index = []
for number, relative in enumerate((
    'ios/Flutter/Generated.xcconfig',
    'ios/Flutter/flutter_export_environment.sh',
    'ios/Flutter/ephemeral/flutter_native_integration.env',
)):
    source = root / relative
    if source.is_symlink():
        sys.exit('Generated Flutter configuration must not be a symbolic link.')
    item = {'path': relative, 'existed': source.exists(), 'copy': str(number)}
    if source.exists():
        shutil.copy2(source, backup / str(number))
    index.append(item)
(backup / 'index.json').write_text(json.dumps(index))
PY
GENERATED_BACKUP_READY=1

# Xcode pre-actions print their inherited environment. Pass only build inputs,
# not API keys, SSH settings or other account/session variables from the caller.
BUILD_ENV=(/usr/bin/env -i "HOME=$HOME" "PATH=$PATH" "TMPDIR=$SIGNING_ROOT/"
  'LANG=en_US.UTF-8' 'LC_ALL=en_US.UTF-8' 'CI=true'
  'FLUTTER_SUPPRESS_ANALYTICS=true' "XCODE_XCCONFIG_FILE=$SIGNING_CONFIG")
for option in DEVELOPER_DIR TOOLCHAINS RUSTUP_TOOLCHAIN PUB_CACHE; do
  if [[ -n "${!option:-}" ]]; then BUILD_ENV+=("$option=${!option}"); fi
done
run_stage() {
  local stage="$1"
  shift
  local build_exit=0
  "${BUILD_ENV[@]}" "$@" >>"$PRIVATE_LOG" 2>&1 || build_exit=$?
  if [[ "$build_exit" != 0 ]]; then
    printf '%s\n' "$stage failed; private build log: $PRIVATE_LOG" >&2
    exit "$build_exit"
  fi
}

cd "$EXAMPLE_DIR"
FLUTTER_ARGS=(build ios "--$BUILD_MODE" --config-only --no-codesign --no-pub
  "--target=$TARGET" "--dart-define-from-file=$SIGNING_ROOT/fixture.json")
if [[ "$BUILD_PLATFORM" == simulator ]]; then FLUTTER_ARGS+=(--simulator); fi
run_stage 'Flutter configuration' "$FLUTTER_COMMAND" "${FLUTTER_ARGS[@]}"

case "$BUILD_MODE" in debug) XCODE_CONFIGURATION=Debug ;; profile) XCODE_CONFIGURATION=Profile ;; release) XCODE_CONFIGURATION=Release ;; esac
if [[ "$BUILD_PLATFORM" == simulator ]]; then
  XCODE_SDK=iphonesimulator
  XCODE_DESTINATION='generic/platform=iOS Simulator'
else
  XCODE_SDK=iphoneos
  XCODE_DESTINATION='generic/platform=iOS'
fi
run_stage 'Xcode build' "$XCODE_COMMAND" -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration "$XCODE_CONFIGURATION" -sdk "$XCODE_SDK" -destination "$XCODE_DESTINATION" \
  -derivedDataPath "$SIGNING_ROOT/DerivedData" -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile "CONFIGURATION_BUILD_DIR=$OUTPUT_DIR/Products" build

APP_BUNDLE="$OUTPUT_DIR/Products/Runner.app"
if [[ "$BUILD_PLATFORM" == physical ]]; then
  run_stage 'Signature verification' "$CODESIGN_COMMAND" --verify --deep --strict "$APP_BUNDLE"
  if ! "${BUILD_ENV[@]}" "$CODESIGN_COMMAND" --display --entitlements :- "$APP_BUNDLE" \
      >"$SIGNING_ROOT/actual-entitlements.plist" 2>>"$PRIVATE_LOG"; then
    printf '%s\n' 'Could not inspect the built fixture signature.' >&2
    exit 1
  fi
fi

"$PYTHON_COMMAND" - "$ROOT_DIR" "$APP_BUNDLE" "$SIGNING_ROOT" "$OUTPUT_DIR" "$BUILD_PLATFORM" "$BUILD_MODE" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, re, subprocess, sys
root, app, temporary, output = map(pathlib.Path, sys.argv[1:5])
platform, mode = sys.argv[5:]
bundle_id = 'work.ianvs.trail.mobileprd'
try:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != bundle_id:
        raise ValueError('Built app does not have the isolated fixture bundle identity.')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or pathlib.Path(executable).name != executable:
        raise ValueError('Built app has no valid executable identity.')
    binary_hash = hashlib.sha256((app / executable).read_bytes()).hexdigest()
    if platform == 'physical':
        entitlements = plistlib.loads((temporary / 'actual-entitlements.plist').read_bytes())
        groups = entitlements.get('keychain-access-groups')
        if not isinstance(groups, list) or len(groups) != 1 or not isinstance(groups[0], str):
            raise ValueError('Built app must have exactly one isolated Keychain group.')
        if not re.fullmatch(r'[A-Z0-9]{10}\.' + re.escape(bundle_id), groups[0]):
            raise ValueError('Built app contains an unexpected Keychain group.')
        if entitlements.get('application-identifier') != groups[0]:
            raise ValueError('Built app application identity and Keychain group do not match.')
        if entitlements.get('com.apple.security.application-groups'):
            raise ValueError('App Groups are not allowed in this fixture build.')
    revision = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True, capture_output=True)
    status = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'], text=True, capture_output=True)
    commit = revision.stdout.strip() if revision.returncode == 0 else None
    metadata = {
        'schema_version': 1,
        'built_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'bundle_id': bundle_id, 'build_platform': platform, 'build_mode': mode,
        'target': 'example/integration_test/mobile_prd_acceptance_test.dart',
        'source_commit': commit,
        'source_tree_clean': not status.stdout if status.returncode == 0 else None,
        'binary_sha256': binary_hash,
        'fixture_sha256': hashlib.sha256((temporary / 'fixture.json').read_bytes()).hexdigest(),
        'target_sha256': hashlib.sha256((root / 'example/integration_test/mobile_prd_acceptance_test.dart').read_bytes()).hexdigest(),
        'app_version': info.get('CFBundleShortVersionString'),
        'app_build': info.get('CFBundleVersion'),
        'signed_keychain_isolation_verified': platform == 'physical',
        'installed': False, 'device_validated': False, 'acceptance_passed': False,
        'private_build_log': 'build.private.log',
    }
    (output / 'build-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
    # Validation errors are fixed strings; never render plist or fixture values.
    message = str(error) if isinstance(error, ValueError) and not isinstance(error, plistlib.InvalidFileException) else 'Could not validate the built fixture artifact.'
    print(message, file=sys.stderr)
    sys.exit(1)
PY
BUILD_SUCCEEDED=1
printf '%s\n' "Built isolated mobile PRD fixture: $OUTPUT_DIR" \
  'Build only: no device installation, launch, account update or acceptance claim.'
