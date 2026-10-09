#!/usr/bin/env bash
# Build an isolated mobile PRD app. Never installs or starts an application.
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
BUNDLE_ID='work.ianvs.trail.mobileprd'
TARGET='integration_test/mobile_prd_acceptance_test.dart'
ENTRYPOINT='smoke'
BUILD_PLATFORM=''
BUILD_MODE=''
SIMULATOR_ARCH=''
FIXTURE_FILE=''
SIGNING_TEAM=''
SIGNING_PROFILE=''
FLUTTER_COMMAND="${FLUTTER:-flutter}"
XCODE_COMMAND="${XCODEBUILD:-xcodebuild}"
CODESIGN_COMMAND="${CODESIGN:-codesign}"
SECURITY_COMMAND="${SECURITY:-security}"
PYTHON_COMMAND="${PYTHON:-python3}"

usage() {
  cat <<'USAGE'
Usage: build_ios_fixture.sh --platform simulator|physical --mode debug|profile|release
       [--entrypoint smoke|app] [--fixture /path/to/defines.json]
       [--simulator-arch arm64|x86_64]
       [--team TEAM_ID --profile PROFILE_UUID]

Simulator supports debug only; --simulator-arch selects one explicit build slice.
Physical builds require an explicitly supplied
team and an already installed provisioning profile UUID; no account discovery,
provisioning updates, device registration, installation or simulator fallback.
Xcode signs automatically using cached profiles, then the artifact must match
the requested profile/team and its actual signer must be authorized by that profile.
The default smoke entrypoint requires a fixture containing TRAIL_MOBILE_PRD_FIXTURE
as a JSON string with runId, ssh, modelBaseUrl and evidenceBaseUrl.
TRAIL_MOBILE_PRD_CASE is optional. The app entrypoint uses lib/main.dart, rejects
--fixture, and lets the user configure API access in the isolated app's settings.
Both entrypoints use the fixed work.ianvs.trail.mobileprd identity and Trail PRD
display name. Normal app data and signing configuration are not copied or changed.
The signed plist opts the app entrypoint into a separate, non-synchronized,
device-only Keychain master key. No master key is supplied by the build.
FLUTTER, XCODEBUILD, CODESIGN, SECURITY and PYTHON may select existing tool executables.
Build products and private logs are written under build/mobile-prd-v1.1/ios.
Do not publish raw build logs: Xcode may include encoded fixture definitions.
USAGE
}

fail_usage() { printf '%s\n' "$1" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--mode|--entrypoint|--fixture|--team|--profile|--simulator-arch)
      [[ $# -ge 2 && -n "$2" ]] || fail_usage 'An option value is missing.'
      case "$1" in
        --platform) BUILD_PLATFORM="$2" ;;
        --mode) BUILD_MODE="$2" ;;
        --entrypoint) ENTRYPOINT="$2" ;;
        --simulator-arch) SIMULATOR_ARCH="$2" ;;
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
case "$ENTRYPOINT" in
  smoke)
    [[ -n "$FIXTURE_FILE" && -f "$FIXTURE_FILE" ]] || fail_usage 'The smoke entrypoint requires a fixture definition file.'
    ;;
  app)
    [[ -z "$FIXTURE_FILE" ]] || fail_usage 'The app entrypoint does not accept a fixture definition file.'
    TARGET='lib/main.dart'
    ;;
  *) fail_usage 'Entrypoint must be smoke or app.' ;;
esac
case "$SIMULATOR_ARCH" in ''|arm64|x86_64) ;; *) fail_usage 'Simulator architecture must be arm64 or x86_64.' ;; esac
if [[ "$BUILD_PLATFORM" == simulator ]]; then
  [[ "$BUILD_MODE" == debug ]] || fail_usage 'Flutter supports iOS simulator builds only in debug mode; no fallback was attempted.'
  [[ -z "$SIGNING_TEAM" && -z "$SIGNING_PROFILE" ]] || fail_usage 'Simulator builds do not accept signing account parameters.'
else
  [[ -z "$SIMULATOR_ARCH" ]] || fail_usage 'Simulator architecture cannot be used for physical builds.'
  [[ "$SIGNING_TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail_usage 'Physical builds require an explicit 10-character Team ID.'
  [[ "$SIGNING_PROFILE" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] || fail_usage 'Physical builds require an explicit existing provisioning profile UUID.'
fi
[[ -f "$EXAMPLE_DIR/$TARGET" ]] || fail_usage 'The selected mobile PRD entrypoint is missing.'
[[ -f "$EXAMPLE_DIR/ios/Runner/Info.plist" ]] || fail_usage 'The Runner Info.plist is missing.'
for tool in "$FLUTTER_COMMAND" "$XCODE_COMMAND" "$PYTHON_COMMAND"; do
  command -v "$tool" >/dev/null 2>&1 || fail_usage 'A required build tool is unavailable.'
done
if [[ "$BUILD_PLATFORM" == physical ]]; then
  command -v "$CODESIGN_COMMAND" >/dev/null 2>&1 || fail_usage 'codesign is required for physical builds.'
  command -v "$SECURITY_COMMAND" >/dev/null 2>&1 || fail_usage 'security is required to inspect the embedded provisioning profile.'
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
  set +e # A failed cache cleanup must not prevent restoring the checkout.
  local restore_failed=0
  # Release rebuildable files before restoring small generated configs. A full
  # disk can otherwise prevent restoration and even mask the original failure.
  if [[ -n "$SIGNING_ROOT" ]]; then rm -rf -- "$SIGNING_ROOT/DerivedData"; fi
  if [[ "$BUILD_SUCCEEDED" != 1 && -n "$OUTPUT_DIR" ]]; then
    rm -rf -- "$OUTPUT_DIR/Products"
  fi
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
      printf '%s\n' 'Could not restore temporary build configuration; keep this checkout idle until reviewed.' >&2
      build_exit=1
      restore_failed=1
    fi
  fi
  if [[ -n "$SIGNING_ROOT" && "$restore_failed" == 0 ]]; then
    rm -rf -- "$SIGNING_ROOT"
  elif [[ "$restore_failed" == 1 ]]; then
    printf '%s\n' "Private recovery backup retained: $SIGNING_ROOT/backup" >&2
  fi
  rmdir "$BUILD_LOCK" 2>/dev/null || true
  exit "$build_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SIGNING_ROOT="$(mktemp -d "$TEMP_BASE/run.XXXXXX")"

# Snapshot only the supplied disposable fixture. Never inspect saved app data,
# secure storage, account credentials or a user SSH configuration.
if [[ "$ENTRYPOINT" == smoke ]]; then
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
fi

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
"$PYTHON_COMMAND" - "$SIGNING_CONFIG" "$SIGNING_ENTITLEMENTS" "$BUILD_PLATFORM" "$SIGNING_TEAM" "$SIMULATOR_ARCH" <<'PY'
import pathlib, sys
config, entitlements, platform, team, simulator_arch = sys.argv[1:]
# The value is a generated local path; reject xcconfig delimiters instead of
# accidentally turning a path into an extra build setting.
if any(c in entitlements for c in ('\n', '\r', '"', '$')):
    sys.exit('The checkout path cannot be represented safely in xcconfig.')
settings = [
    'PRODUCT_BUNDLE_IDENTIFIER = work.ianvs.trail.mobileprd',
    # xcconfig scalar path values retain literal quotes. The complete raw
    # value also preserves spaces, as in the repository's signed Apple build.
    f'CODE_SIGN_ENTITLEMENTS = {entitlements}',
    'CODE_SIGNING_ALLOWED = ' + ('YES' if platform == 'physical' else 'NO'),
]
if simulator_arch:
    settings += [f'ARCHS = {simulator_arch}', 'ONLY_ACTIVE_ARCH = YES']
if platform == 'physical':
    # Xcode-managed profiles require Automatic. Do not apply a global profile
    # specifier to Swift package targets, which cannot use provisioning profiles.
    # No provisioning-update flags are passed; inspect the signed result below.
    settings += ['CODE_SIGN_STYLE = Automatic', 'CODE_SIGN_IDENTITY = Apple Development',
                 f'DEVELOPMENT_TEAM = {team}']
pathlib.Path(config).write_text('\n'.join(settings) + '\n')
PY

# Flutter writes generated configuration even with --config-only. Info.plist is
# changed only for this isolated artifact. Restore all original bytes/modes on
# success and every failure, including an Info.plist validation failure.
"$PYTHON_COMMAND" - "$EXAMPLE_DIR" "$SIGNING_ROOT/backup" <<'PY'
import json, pathlib, shutil, sys
root, backup = map(pathlib.Path, sys.argv[1:])
backup.mkdir()
index = []
for number, relative in enumerate((
    'ios/Flutter/Generated.xcconfig',
    'ios/Flutter/flutter_export_environment.sh',
    'ios/Flutter/ephemeral/flutter_native_integration.env',
    'ios/Runner/Info.plist',
)):
    source = root / relative
    if source.is_symlink():
        sys.exit('Temporary build configuration must not be a symbolic link.')
    item = {'path': relative, 'existed': source.exists(), 'copy': str(number)}
    if source.exists():
        shutil.copy2(source, backup / str(number))
    index.append(item)
(backup / 'index.json').write_text(json.dumps(index))
PY
GENERATED_BACKUP_READY=1

# Record source provenance before applying the temporary tracked plist change.
"$PYTHON_COMMAND" - "$ROOT_DIR" "$SIGNING_ROOT/source.json" <<'PY'
import json, pathlib, subprocess, sys
root, destination = map(pathlib.Path, sys.argv[1:])
revision = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True, capture_output=True)
status = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'], text=True, capture_output=True)
destination.write_text(json.dumps({
    'source_commit': revision.stdout.strip() if revision.returncode == 0 else None,
    'source_tree_clean': not status.stdout if status.returncode == 0 else None,
}))
PY

"$PYTHON_COMMAND" - "$EXAMPLE_DIR/ios/Runner/Info.plist" "$BUILD_PLATFORM" "$ENTRYPOINT" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
try:
    info = plistlib.loads(path.read_bytes())
    if not isinstance(info, dict):
        raise ValueError()
    info['CFBundleDisplayName'] = 'Trail PRD'
    info['CFBundleName'] = 'Trail PRD'
    info['TrailPrdDeviceLocalMasterKey'] = True
    if sys.argv[2] == 'physical':
        info['NSLocalNetworkUsageDescription'] = (
            'Trail PRD connects to the SSH, model API and evidence fixtures you '
            'provide on your local network for acceptance testing.'
            if sys.argv[3] == 'smoke' else
            'Trail PRD connects to the SSH hosts and model APIs you configure '
            'on your local network.'
        )
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
    sys.exit('Could not prepare the isolated app Info.plist; original contents will be restored.')
PY

# Xcode pre-actions print their inherited environment. Pass only build inputs,
# not API keys, SSH settings or other account/session variables from the caller.
BUILD_ENV=(/usr/bin/env -i "HOME=$HOME" "PATH=$PATH" "TMPDIR=$SIGNING_ROOT/"
  'LANG=en_US.UTF-8' 'LC_ALL=en_US.UTF-8' 'CI=true'
  'FLUTTER_SUPPRESS_ANALYTICS=true' "XCODE_XCCONFIG_FILE=$SIGNING_CONFIG")
for option in USER LOGNAME SHELL __CF_USER_TEXT_ENCODING DEVELOPER_DIR TOOLCHAINS RUSTUP_TOOLCHAIN PUB_CACHE; do
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
  "--target=$TARGET")
if [[ "$ENTRYPOINT" == smoke ]]; then
  FLUTTER_ARGS+=("--dart-define-from-file=$SIGNING_ROOT/fixture.json")
fi
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
  run_stage 'Signing certificate inspection' "$CODESIGN_COMMAND" --display \
    "--extract-certificates=$SIGNING_ROOT/actual-certificate-" "$APP_BUNDLE"
  if ! "${BUILD_ENV[@]}" "$SECURITY_COMMAND" cms -D -i "$APP_BUNDLE/embedded.mobileprovision" \
      >"$SIGNING_ROOT/actual-profile.plist" 2>>"$PRIVATE_LOG"; then
    printf '%s\n' 'Could not inspect the built fixture provisioning profile.' >&2
    exit 1
  fi
fi

"$PYTHON_COMMAND" - "$ROOT_DIR" "$APP_BUNDLE" "$SIGNING_ROOT" "$OUTPUT_DIR" "$BUILD_PLATFORM" "$BUILD_MODE" "$SIMULATOR_ARCH" "$ENTRYPOINT" "$TARGET" "$SIGNING_TEAM" "$SIGNING_PROFILE" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, re, sys
root, app, temporary, output = map(pathlib.Path, sys.argv[1:5])
platform, mode, simulator_arch, entrypoint, target, team, requested_profile = sys.argv[5:]
bundle_id = 'work.ianvs.trail.mobileprd'
try:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != bundle_id:
        raise ValueError('Built app does not have the isolated fixture bundle identity.')
    if info.get('CFBundleDisplayName') != 'Trail PRD':
        raise ValueError('Built app does not have the isolated Trail PRD display name.')
    if info.get('TrailPrdDeviceLocalMasterKey') is not True:
        raise ValueError('Built app does not opt into the isolated device-only master key policy.')
    if platform == 'physical' and (
        not isinstance(info.get('NSLocalNetworkUsageDescription'), str)
        or not info['NSLocalNetworkUsageDescription'].strip()
    ):
        raise ValueError('Physical acceptance app has no local network usage description.')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or pathlib.Path(executable).name != executable:
        raise ValueError('Built app has no valid executable identity.')
    binary_hash = hashlib.sha256((app / executable).read_bytes()).hexdigest()
    signer_sha1 = None
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
        expected_identity = team + '.' + bundle_id
        if (entitlements.get('application-identifier') != expected_identity
                or entitlements.get('com.apple.developer.team-identifier') != team):
            raise ValueError('Built app signature does not match the requested team.')
        profile = plistlib.loads((temporary / 'actual-profile.plist').read_bytes())
        if (not isinstance(profile, dict)
                or profile.get('UUID', '').lower() != requested_profile.lower()
                or profile.get('TeamIdentifier') != [team]):
            raise ValueError('Built app does not contain the requested provisioning profile and team.')
        profile_entitlements = profile.get('Entitlements', {})
        if (profile_entitlements.get('application-identifier') != expected_identity
                or profile_entitlements.get('com.apple.developer.team-identifier') != team):
            raise ValueError('Embedded provisioning profile does not authorize the isolated app identity.')
        expiration = profile.get('ExpirationDate')
        if (not isinstance(expiration, datetime.datetime)
                or expiration.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc)):
            raise ValueError('Embedded provisioning profile has expired or has no valid expiration date.')
        certificate = (temporary / 'actual-certificate-0').read_bytes()
        if certificate not in profile.get('DeveloperCertificates', []):
            raise ValueError('Actual signing certificate is not authorized by the requested provisioning profile.')
        signer_sha1 = hashlib.sha1(certificate).hexdigest().upper()
    source = json.loads((temporary / 'source.json').read_text())
    is_smoke = entrypoint == 'smoke'
    metadata = {
        'schema_version': 1,
        'built_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'bundle_id': bundle_id, 'build_platform': platform, 'build_mode': mode,
        'requested_simulator_arch': simulator_arch or None,
        'entrypoint': entrypoint, 'target': 'example/' + target,
        'is_smoke': is_smoke, 'isolated': True,
        'display_name': info['CFBundleDisplayName'],
        'master_key_opt_in_verified': True,
        'master_key_policy': 'unused_in_memory_smoke' if is_smoke else 'acceptance_device_only_keychain',
        **source,
        'binary_sha256': binary_hash,
        'fixture_included': is_smoke,
        'fixture_sha256': hashlib.sha256((temporary / 'fixture.json').read_bytes()).hexdigest() if is_smoke else None,
        'target_sha256': hashlib.sha256((root / 'example' / target).read_bytes()).hexdigest(),
        'app_version': info.get('CFBundleShortVersionString'),
        'app_build': info.get('CFBundleVersion'),
        'signed_keychain_isolation_verified': platform == 'physical',
        'embedded_profile_verified': platform == 'physical',
        'signing_style': 'automatic_offline' if platform == 'physical' else None,
        'signing_certificate_sha1': signer_sha1,
        'local_network_usage_declared': bool(info.get('NSLocalNetworkUsageDescription')),
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
printf '%s\n' "Built isolated mobile PRD $ENTRYPOINT entrypoint: $OUTPUT_DIR" \
  'Build only: no device installation, launch, account update or acceptance claim.'
