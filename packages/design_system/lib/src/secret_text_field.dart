// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// A masked text field with a reveal toggle, for API keys and passwords.
///
/// Obscured by default. Suggestions, autocorrect, personalised IME learning
/// and autofill are off. [onRevealChanged] lets the feature set the platform
/// secure flag (no screenshots) while a secret is visible.
class SecretTextField extends StatefulWidget {
  const SecretTextField({
    required this.label,
    required this.showTooltip,
    required this.hideTooltip,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onRevealChanged,
    this.validator,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.autovalidateMode,
    super.key,
  });

  final String label;

  /// Tooltip and accessible name of the toggle while the value is hidden.
  final String showTooltip;

  /// Tooltip and accessible name of the toggle while the value is visible.
  final String hideTooltip;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<bool>? onRevealChanged;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final AutovalidateMode? autovalidateMode;

  @override
  State<SecretTextField> createState() => _SecretTextFieldState();
}

class _SecretTextFieldState extends State<SecretTextField> {
  bool _revealed = false;

  void _toggle() {
    setState(() => _revealed = !_revealed);
    widget.onRevealChanged?.call(_revealed);
  }

  @override
  void dispose() {
    // Leaving the screen with a revealed secret must lift the secure flag
    // request: tell the owner it is hidden again.
    if (_revealed) widget.onRevealChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: !_revealed,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: null,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _revealed ? widget.hideTooltip : widget.showTooltip,
          icon: Icon(
            _revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: widget.enabled ? _toggle : null,
        ),
      ),
    );
  }
}
