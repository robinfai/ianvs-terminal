#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"

(
  cd "$EXAMPLE_DIR"

  flutter analyze

  DEEPSEEK_API_KEY= \
  OPENAI_API_KEY= \
  ANTHROPIC_API_KEY= \
  GOOGLE_API_KEY= \
  GROQ_API_KEY= \
  MISTRAL_API_KEY= \
  flutter test \
    test/config/local_terminal_config_models_test.dart \
    test/config/local_terminal_config_repository_test.dart \
    test/config/local_terminal_config_bootstrap_test.dart \
    test/command_center/command_center_feature_flags_test.dart \
    test/agent_center \
    test/command_center/command_center_mode_router_test.dart \
    test/command_center/command_search_overlay_controller_test.dart \
    test/command_center/command_search_overlay_test.dart \
    test/shell/shell_screen_command_blocks_test.dart
)
