import 'package:flutter/material.dart';

String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.length < 8 ||
      password.length > 128 ||
      !RegExp(r'[a-zA-Z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return 'Dùng 8–128 ký tự, gồm chữ cái và số.';
  }
  return null;
}

class PasswordInput extends StatefulWidget {
  const PasswordInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.enabled = true,
    this.newPassword = false,
    this.helper,
  });
  final TextEditingController controller;
  final String label, hint;
  final String? helper;
  final String? Function(String?) validator;
  final bool enabled, newPassword;
  @override
  State<PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      helperText: widget.helper,
      helperMaxLines: 3,
      errorMaxLines: 3,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: '${hidden ? 'Hiện' : 'Ẩn'} ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => hidden = !hidden)
            : null,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
