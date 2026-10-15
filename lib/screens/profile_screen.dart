import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth/account_actions.dart';
import 'auth/auth_error.dart';
import 'auth/auth_text_field.dart' show optionalPhoneValidator, designationValidator;
import 'legal/privacy_policy_screen.dart';
import 'legal/terms_of_service_screen.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/recruiter_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/app_toast.dart';
import 'account/account_security_screen.dart';
import 'recruiter/company_profile_screen.dart';
import '../widgets/email_toggle_tile.dart';

/// Recruiter's own editable profile -- a tab in the bottom nav, not a
/// candidate's profile. [RecruiterProfileService] (local cache) just
/// pre-fills the form instantly; the backend `users` row -- the same
/// doc filled in at signup/[CompleteProfileScreen] -- is the real source
/// of truth, so [_loadFromAccount] re-hydrates from it on every open and
/// [_save] writes back to it.
class ProfileScreen extends StatefulWidget {
  /// Defaults to [AuthService.instance]; tests pass one wired to fakes.
  final AuthService? authService;
  const ProfileScreen({super.key, this.authService});

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

  AuthService get _auth => widget.authService ?? AuthService.instance;

  // One focus node per editable field, so a failed save can jump straight
  // to the first field that needs fixing (focusing it scrolls it into view).
  final _nameFocus = FocusNode();
  final _designationFocus = FocusNode();
  final _companyFocus = FocusNode();
  final _phoneFocus = FocusNode();

  /// The values as last saved (or loaded), to tell "Unsaved changes" from
  /// "All changes saved" and to skip a pointless save.
  String _savedSnapshot = '';
  bool _saving = false;
  bool _emailNotifications = true;

  String get _currentSnapshot => [
        _name.text.trim(),
        _designation.text.trim(),
        _company.text.trim(),
        _phone.text.trim(),
      ].join('\u0001');

  bool get _dirty => _currentSnapshot != _savedSnapshot;

  @override
  void initState() {
    super.initState();
    final service = RecruiterProfileService.instance;
    _name = TextEditingController(text: service.name);
    _designation = TextEditingController(text: service.designation);
    _company = TextEditingController(text: service.company);
    _email = TextEditingController(text: service.email);
    _phone = TextEditingController(text: service.phone);
    _savedSnapshot = _currentSnapshot;
    _loadFromAccount();
  }

  /// Pulls the signed-in recruiter's real profile from `users/{uid}` and
  /// overwrites whatever the local cache had -- fixes the cache starting
  /// empty on a fresh browser/device even though the account's data
  /// already exists from signup.
  Future<void> _loadFromAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final profile = await _auth.fetchProfile(uid);
    if (!mounted || profile == null) return;
    _name.text = profile.name;
    _designation.text = profile.designation;
    _company.text = profile.company;
    _email.text = profile.email;
    _phone.text = profile.phone;
    setState(() {
      _savedSnapshot = _currentSnapshot;
      _emailNotifications = profile.emailNotifications;
    });
    await RecruiterProfileService.instance.save(
      name: profile.name,
      designation: profile.designation,
      company: profile.company,
      email: profile.email,
      phone: profile.phone,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _company.dispose();
    _email.dispose();
    _phone.dispose();
    _nameFocus.dispose();
    _designationFocus.dispose();
    _companyFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  /// Every field that currently fails validation, in form order. Run by
  /// hand (not only through [FormState.validate]) so a failed save can name
  /// the problem in a toast and focus the first offending field.
  List<({String label, String message, FocusNode focus})> _problems() {
    final out = <({String label, String message, FocusNode focus})>[];
    if (_name.text.trim().isEmpty) {
      out.add((label: 'Full name', message: 'Required', focus: _nameFocus));
    }
    final designation = _designation.text.trim();
    if (designation.isNotEmpty) {
      final message = designationValidator(designation);
      if (message != null) out.add((label: 'Designation', message: message, focus: _designationFocus));
    }
    final phoneMessage = optionalPhoneValidator(_phone.text);
    if (phoneMessage != null) out.add((label: 'Phone', message: phoneMessage, focus: _phoneFocus));
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final problems = _problems();
    if (problems.isNotEmpty) {
      _formKey.currentState?.validate(); // paint the inline messages too
      problems.first.focus.requestFocus();
      final first = problems.first;
      AppToast.warning(
        problems.length == 1 ? 'One detail needs fixing' : '${problems.length} details need fixing',
        description: '${first.label}: ${first.message}',
      );
      return;
    }

    if (!_dirty) {
      AppToast.info('Nothing to save', description: 'Your profile is already up to date.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _auth.updateRecruiterProfile(
        name: _name.text.trim(),
        designation: _designation.text.trim(),
        company: _company.text.trim(),
        phone: _phone.text.trim(),
      );
      await RecruiterProfileService.instance.save(
        name: _name.text.trim(),
        designation: _designation.text.trim(),
        company: _company.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      setState(() => _savedSnapshot = _currentSnapshot);
      AppToast.success('Profile saved', description: 'Your details are up to date.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppToast.error('Could not save your profile', description: authErrorMessage(e));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'ProfileScreen: save failed');
      if (!mounted) return;
      AppToast.error('Could not save your profile', description: 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                const SizedBox(height: 12),
                Center(child: _SaveStatusChip(dirty: _dirty, saving: _saving)),
                const SizedBox(height: 20),
                FadeInUp(delay: const Duration(milliseconds: 40), child: _field(_name, 'Full name', Icons.person_outline, required: true, focusNode: _nameFocus)),
                const SizedBox(height: 14),
                FadeInUp(delay: const Duration(milliseconds: 80), child: _field(_designation, 'Designation', Icons.badge_outlined, focusNode: _designationFocus, validator: (v) => (v == null || v.trim().isEmpty) ? null : designationValidator(v))),
                const SizedBox(height: 14),
                FadeInUp(delay: const Duration(milliseconds: 120), child: _field(_company, 'Company', Icons.apartment_rounded, focusNode: _companyFocus)),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 160),
                  child: _field(
                    _email,
                    'Email',
                    Icons.email_outlined,
                    readOnly: true,
                    helper: 'This is your login email, so it cannot be changed here.',
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _field(_phone, 'Phone', Icons.phone_outlined, keyboardType: TextInputType.phone, focusNode: _phoneFocus, validator: optionalPhoneValidator),
                ),
                const SizedBox(height: 28),
                FadeInUp(
                  delay: const Duration(milliseconds: 240),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save changes'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 260),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CompanyProfileScreen()),
                    ),
                    icon: const Icon(Icons.apartment_rounded),
                    label: const Text('Company page & verification'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 265),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountSecurityScreen()),
                    ),
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Account security'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 270),
                  child: EmailToggleTile(initialValue: _emailNotifications),
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
                  delay: const Duration(milliseconds: 300),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                          child: const Text('Privacy Policy', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
                          child: const Text('Terms of Service', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 320),
                  child: OutlinedButton.icon(
                    onPressed: () => _auth.signOut(),
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
    FocusNode? focusNode,
    bool readOnly = false,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: readOnly ? AppColors.textSecondary : AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: readOnly ? const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textTertiary) : null,
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

/// "All changes saved" / "Unsaved changes" under the avatar, so the state of
/// the form is visible without waiting for a toast.
class _SaveStatusChip extends StatelessWidget {
  final bool dirty;
  final bool saving;
  const _SaveStatusChip({required this.dirty, required this.saving});

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = saving
        ? (AppColors.info, Icons.sync_rounded, 'Saving...')
        : dirty
            ? (AppColors.warning, Icons.edit_note_rounded, 'Unsaved changes')
            : (AppColors.like, Icons.check_circle_rounded, 'All changes saved');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
