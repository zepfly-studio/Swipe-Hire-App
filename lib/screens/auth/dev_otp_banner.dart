import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Shows the OTP in-app while the backend has no email provider configured
/// (it returns the code in the send response -- see `backend/README.md`).
/// Renders nothing once [otp] is empty, i.e. once codes are really emailed.
class DevOtpBanner extends StatelessWidget {
  final String otp;
  const DevOtpBanner({super.key, required this.otp});

  @override
  Widget build(BuildContext context) {
    if (otp.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accentAlt.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.code_rounded, color: AppColors.accentAlt, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                  children: [
                    const TextSpan(text: 'Email sending is not set up yet. Your code is '),
                    TextSpan(
                      text: otp,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
