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

/// A phone number: 10 to 13 digits, optionally starting with `+`; spaces,
/// dashes and brackets are ignored. Rejects text like "wdwcde2".
String? phoneValidator(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Required';
  final cleaned = v.replaceAll(RegExp(r'[\s\-()]'), '');
  return RegExp(r'^\+?\d{10,13}$').hasMatch(cleaned) ? null : 'Enter a valid phone number (10 digits)';
}

/// Same as [phoneValidator] but a blank value is allowed.
String? optionalPhoneValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return phoneValidator(value);
}

/// A job title such as "HR Manager": starts with a letter, at least two
/// letters in total, only letters, digits and common punctuation.
String? designationValidator(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Required';
  final letters = RegExp(r'[A-Za-z]').allMatches(v).length;
  final valid = RegExp(r"^[A-Za-z][A-Za-z0-9 .,&/'()-]{1,59}$").hasMatch(v);
  return (valid && letters >= 2) ? null : 'Enter a valid designation, e.g. HR Manager';
}

String? emailValidator(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Required';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  return valid ? null : 'Enter a valid email';
}
