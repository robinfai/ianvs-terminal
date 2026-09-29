import 'package:flutter/material.dart';

import 'terminal_composer_controller.dart';

/// Semantic names for the existing Material outline glyph family.
///
/// Trail maps this family to its bundled, licensed Material Symbols Outlined
/// font. Other hosts retain their standard Material font without a new asset
/// or dependency. Labels and toggle/selection semantics belong to the control.
abstract final class ComposerIcons {
  static const IconData terminal = Icons.terminal_outlined;
  static const IconData localTarget = Icons.desktop_windows_outlined;
  static const IconData remoteTarget = Icons.dns_outlined;
  static const IconData directory = Icons.folder_open_outlined;
  static const IconData history = Icons.history_outlined;
  static const IconData automaticSuggestions =
      Icons.format_list_bulleted_outlined;
  static const IconData automaticSuggestionsOn = Icons.toggle_on_outlined;
  static const IconData automaticSuggestionsOff = Icons.toggle_off_outlined;
  static const IconData shortcuts = Icons.keyboard_outlined;
  static const IconData more = Icons.more_horiz_outlined;
  static const IconData copy = Icons.content_copy_outlined;
  static const IconData undo = Icons.undo_outlined;
  static const IconData redo = Icons.redo_outlined;
  static const IconData useTerminal = Icons.input_outlined;
  static const IconData accept = Icons.keyboard_return_outlined;
  static const IconData run = Icons.play_arrow_outlined;
  static const IconData ready = Icons.check_circle_outline;
  static const IconData sending = Icons.sync_outlined;
  static const IconData running = Icons.hourglass_top_outlined;
  static const IconData suspended = Icons.input_outlined;
  static const IconData draft = Icons.edit_note_outlined;
  static const IconData unknown = Icons.warning_amber_outlined;
  static const IconData file = Icons.insert_drive_file_outlined;
  static const IconData option = Icons.flag_outlined;
  static const IconData alias = Icons.shortcut_outlined;
  static const IconData script = Icons.play_circle_outline;
  static const IconData argument = Icons.code_outlined;
  static const IconData close = Icons.close_outlined;
  static const IconData chevronDown = Icons.keyboard_arrow_down_outlined;
  static const IconData check = Icons.check_outlined;
  static const IconData search = Icons.search_outlined;
  static const IconData clear = Icons.backspace_outlined;
  static const IconData recover = Icons.restore_outlined;

  static IconData forOwnership(ComposerOwnership ownership) =>
      switch (ownership) {
        ComposerOwnership.ready => ready,
        ComposerOwnership.submitting => sending,
        ComposerOwnership.running => running,
        ComposerOwnership.suspended => suspended,
        ComposerOwnership.draft => draft,
        ComposerOwnership.unknown => unknown,
      };

  static IconData forKind(String kind, {bool riskHint = false}) => riskHint
      ? unknown
      : switch (kind) {
          'directory' || 'folder' => directory,
          'file' => file,
          'option' => option,
          'alias' => alias,
          'script' => script,
          'command' || 'subcommand' => terminal,
          _ => argument,
        };
}
