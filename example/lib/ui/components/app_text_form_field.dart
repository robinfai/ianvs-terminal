import 'package:flutter/material.dart';

/// Keeps Material's editing/IME, autofill and Form contracts. Password reveal
/// changes only obscuring; it never replaces the controller or selection.
class AppTextFormField extends StatefulWidget {
  const AppTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.validator,
    this.onSaved,
    this.onChanged,
    this.onFieldSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.readOnly = false,
    this.password = false,
    this.revealLabel,
    this.concealLabel,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  }) : assert(
         !password || (revealLabel != null && concealLabel != null),
         'Password fields require localized reveal and conceal labels.',
       );

  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final FormFieldSetter<String>? onSaved;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool readOnly;
  final bool password;
  final String? revealLabel;
  final String? concealLabel;
  final AutovalidateMode autovalidateMode;

  @override
  State<AppTextFormField> createState() => _AppTextFormFieldState();
}

class _AppTextFormFieldState extends State<AppTextFormField> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    initialValue: widget.initialValue,
    focusNode: widget.focusNode,
    enabled: widget.enabled,
    readOnly: widget.readOnly,
    obscureText: widget.password && !_revealed,
    autocorrect: !widget.password,
    enableSuggestions: !widget.password,
    keyboardType: widget.keyboardType,
    textInputAction: widget.textInputAction,
    autofillHints: widget.autofillHints,
    validator: widget.validator,
    autovalidateMode: widget.autovalidateMode,
    onSaved: widget.onSaved,
    onChanged: widget.onChanged,
    onFieldSubmitted: widget.onFieldSubmitted,
    decoration: widget.password
        ? widget.decoration.copyWith(
            suffixIcon: IconButton(
              tooltip: _revealed ? widget.concealLabel : widget.revealLabel,
              isSelected: _revealed,
              onPressed: widget.enabled
                  ? () => setState(() => _revealed = !_revealed)
                  : null,
              icon: const Icon(Icons.visibility_outlined),
              selectedIcon: const Icon(Icons.visibility_off_outlined),
            ),
          )
        : widget.decoration,
  );
}
