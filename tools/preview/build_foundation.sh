#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
flutter pub get --enforce-lockfile
cd example
flutter gen-l10n
flutter test test/ui/app_dropdown_form_field_test.dart test/ui/app_theme_contract_test.dart test/ui/cupertino_foundation_test.dart
flutter build web --release --target lib/component_preview.dart --no-web-resources-cdn --base-href /
