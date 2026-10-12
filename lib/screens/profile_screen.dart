import 'package:flutter/material.dart';
import 'auth/account_actions.dart';
import '../services/auth_service.dart';
import '../services/recruiter_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';

/// Recruiter's own editable profile -- a tab in the bottom nav, not a
/// candidate's profile. Saved locally with [RecruiterProfileService].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _designation;
  late final TextEditingController _company;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final service = RecruiterProfileService.instance;
    _name = TextEditingController(text: service.name);
    _designation = TextEditingController(text: service.designation);
    _company = TextEditingController(text: service.company);
    _email = TextEditingController(text: service.email);
    _phone = TextEditingController(text: service.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _company.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await RecruiterProfileService.instance.save(
      name: _name.text.trim(),
      designation: _designation.text.trim(),
      company: _company.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Profile saved'),
        backgroundColor: AppColors.surfaceAlt,
        behavior: SnackBarBehavior.floating,
      ));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _name.text.trim().isEmpty ? 'Recruiter' : _name.text.trim();

    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                const Text('My Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                FadeInUp(
                  child: Center(
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: ClipOval(child: InitialsAvatar(name: displayName)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeInUp(delay: const Duration(milliseconds: 40), child: _field(_name, 'Full name', Icons.person_outline, required: true)),
                const SizedBox(height: 14),
                FadeInUp(delay: const Duration(milliseconds: 80), child: _field(_designation, 'Designation', Icons.badge_outlined)),
                const SizedBox(height: 14),
                FadeInUp(delay: const Duration(milliseconds: 120), child: _field(_company, 'Company', Icons.apartment_rounded)),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 160),
                  child: _field(
                    _email,
                    'Email',
                    Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
                      return valid ? null : 'Enter a valid email';
                    },
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _field(_phone, 'Phone', Icons.phone_outlined, keyboardType: TextInputType.phone),
                ),
                const SizedBox(height: 28),
                FadeInUp(
                  delay: const Duration(milliseconds: 240),
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Changes'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 280),
                  child: OutlinedButton.icon(
                    onPressed: () => showExportDataDialog(context),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export my data'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 320),
                  child: OutlinedButton.icon(
                    onPressed: () => AuthService.instance.signOut(),
                    icon: const Icon(Icons.logout_rounded, color: AppColors.reject),
                    label: const Text('Log out', style: TextStyle(color: AppColors.reject)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: AppColors.reject),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 360),
                  child: TextButton.icon(
                    onPressed: () => confirmAndDeleteAccount(context),
                    icon: const Icon(Icons.delete_forever_outlined, color: AppColors.reject, size: 18),
                    label: const Text('Delete account', style: TextStyle(color: AppColors.reject)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      validator: validator ??
          (required
              ? (value) => (value == null || value.trim().isEmpty) ? 'Required' : null
              : null),
    );
  }
}
