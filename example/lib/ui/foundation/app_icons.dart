import 'package:flutter/material.dart';

/// Semantic icon vocabulary for IDE chrome and configuration surfaces.
/// Keep actions recognizable across dialogs; state is expressed by the control
/// (selection, focus, disabled color), not an unrelated replacement glyph.
abstract final class AppIcons {
  static const IconData settings = Icons.settings_outlined;
  static const IconData general = Icons.tune_outlined;
  static const IconData appearance = Icons.palette_outlined;
  static const IconData shortcuts = Icons.keyboard_outlined;
  static const IconData security = Icons.shield_outlined;
  static const IconData data = Icons.storage_outlined;
  static const IconData profile = Icons.badge_outlined;
  static const IconData startup = Icons.play_circle_outline;
  static const IconData terminal = Icons.terminal_outlined;
  static const IconData automation = Icons.bolt_outlined;
  static const IconData advanced = Icons.settings_applications_outlined;
  static const IconData search = Icons.search_outlined;
  static const IconData close = Icons.close_outlined;
  static const IconData add = Icons.add_outlined;
  static const IconData remove = Icons.delete_outline;
  static const IconData restore = Icons.restart_alt_outlined;
  static const IconData save = Icons.save_outlined;
  static const IconData more = Icons.more_horiz_outlined;
  static const IconData back = Icons.arrow_back_outlined;
  static const IconData forward = Icons.chevron_right_outlined;
  static const IconData server = Icons.dns_outlined;
  static const IconData local = Icons.computer_outlined;
  static const IconData folder = Icons.folder_open_outlined;
  static const IconData key = Icons.key_outlined;
  static const IconData copy = Icons.content_copy_outlined;
  static const IconData connect = Icons.login_outlined;
  static const IconData information = Icons.info_outline;
  static const IconData warning = Icons.warning_amber_outlined;
  static const IconData error = Icons.error_outline;
  static const IconData success = Icons.check_circle_outline;
}

/// Glyph extent is separate from the platform's minimum pointer/touch target.
abstract final class AppIconSize {
  static const inline = 16.0;
  static const toolbar = 16.0;
  static const navigation = 20.0;
  static const touch = 20.0;
}
