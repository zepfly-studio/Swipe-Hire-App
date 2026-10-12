import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Shared field chrome for every field on the login/signup screens, so they
/// all match the dark "surface card" look used across the rest of the app.
InputDecoration authFieldDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );
}

String? requiredValidator(String? value) =>
    (value == null || value.trim().isEmpty) ? 'Required' : null;

String? emailValidator(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Required';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  return valid ? null : 'Enter a valid email';
}
