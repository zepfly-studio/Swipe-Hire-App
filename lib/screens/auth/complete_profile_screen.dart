import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate_profile.dart';
import '../../services/auth_service.dart';
import '../../services/candidate_profile_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../services/error_reporter.dart';
import 'auth_gate.dart';
import 'auth_text_field.dart';
import '../../widgets/app_toast.dart';

/// Shown once, right after signup (or on a later login if the account
/// never finished it) -- collects the remaining role-specific details
/// before [AuthGate] will route into the real app. Recruiters fill in
/// designation/phone; candidates fill in a full hiring profile.
class CompleteProfileScreen extends StatefulWidget {
  final AppUser user;

  /// When set, this screen is being reopened from the candidate's own
  /// dashboard to edit an already-complete profile (pre-fills the form and
  /// pops back with the result instead of routing to the home screen).
  final CandidateProfile? existingCandidateProfile;

  const CompleteProfileScreen({super.key, required this.user, this.existingCandidateProfile});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Recruiter fields
  final _designation = TextEditingController();
  final _recruiterPhone = TextEditingController();

  // Candidate fields
  final _age = TextEditingController();
  final _qualification = TextEditingController();
  final _experience = TextEditingController();
  final _desiredRole = TextEditingController();
  final _location = TextEditingController();
  final _skills = TextEditingController();
  final _expectedSalary = TextEditingController();
  final _noticePeriod = TextEditingController();
  final _about = TextEditingController();
  final _currentCompany = TextEditingController();
  final _currentSalary = TextEditingController();

  // Candidate media -- the same photo/resume/intro video recruiters see
  // (double-tap for resume, swipe for video) on the swipe-deck card.
  String _photoUrl = '';
  String _resumeUrl = '';
  String _introVideoUrl = '';
  String? _uploadingSlot;

  bool _loading = false;

  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const int _maxResumeBytes = 5 * 1024 * 1024;
  static const int _maxVideoBytes = 50 * 1024 * 1024;

  bool get _isRecruiter => widget.user.role == UserRole.recruiter;
  bool get _isEditMode => widget.existingCandidateProfile != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingCandidateProfile;
    if (existing != null) {
      _age.text = existing.age > 0 ? existing.age.toString() : '';
      _qualification.text = existing.qualification;
      _experience.text = existing.experience;
      _desiredRole.text = existing.desiredRole;
      _location.text = existing.location;
      _skills.text = existing.skills.join(', ');
      _expectedSalary.text = existing.expectedSalaryLpa > 0 ? existing.expectedSalaryLpa.toString() : '';
      _noticePeriod.text = existing.noticePeriod;
      _about.text = existing.about;
      _currentCompany.text = existing.currentCompany;
      _currentSalary.text = existing.currentSalaryLpa > 0 ? existing.currentSalaryLpa.toString() : '';
      _photoUrl = existing.photoUrl;
      _resumeUrl = existing.resumeUrl;
      _introVideoUrl = existing.introVideoUrl;
    }
  }

  @override
  void dispose() {
    _designation.dispose();
    _recruiterPhone.dispose();
    _age.dispose();
    _qualification.dispose();
    _experience.dispose();
    _desiredRole.dispose();
    _location.dispose();
    _skills.dispose();
    _expectedSalary.dispose();
    _noticePeriod.dispose();
    _about.dispose();
    _currentCompany.dispose();
    _currentSalary.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload({
    required String slot,
    required FileType fileType,
    required int maxBytes,
    List<String>? allowedExtensions,
    required Future<String> Function(PlatformFile) upload,
    required ValueChanged<String> onUploaded,
  }) async {
    final files = await FilePicker.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions,
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null || !mounted) return;

    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > maxBytes) {
      _showMessage('${file.name} is ${_formatBytes(size)} -- max allowed is ${_formatBytes(maxBytes)}.');
      return;
    }

    setState(() => _uploadingSlot = slot);
    try {
      final url = await upload(file);
      if (!mounted) return;
      setState(() {
        onUploaded(url);
        _uploadingSlot = null;
      });
      _showMessage('${file.name} uploaded', isError: false);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompleteProfileScreen: upload $slot failed');
      if (!mounted) return;
      setState(() => _uploadingSlot = null);
      _showMessage('Upload failed. Please try again.');
    }
  }

  /// Hands control back to a fresh [AuthGate], which re-reads the (now
  /// complete) profile and routes to the right home screen. Going straight
  /// to a shell with `pushReplacement` would remove the AuthGate that
  /// listens for sign-out, leaving Log out unable to leave the app.
  void _backToAuthGate() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      AppToast.warning('Some details need fixing', description: 'Check the fields marked in red and try again.');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_isRecruiter) {
        await AuthService.instance.completeRecruiterProfile(
          designation: _designation.text,
          phone: _recruiterPhone.text,
        );
        await RecruiterProfileService.instance.save(
          name: widget.user.name,
          designation: _designation.text.trim(),
          company: widget.user.company,
          email: widget.user.email,
          phone: _recruiterPhone.text.trim(),
        );
        if (!mounted) return;
        _backToAuthGate();
      } else {
        final profile = CandidateProfile(
          age: int.tryParse(_age.text.trim()) ?? 0,
          qualification: _qualification.text.trim(),
          experience: _experience.text.trim(),
          desiredRole: _desiredRole.text.trim(),
          location: _location.text.trim(),
          skills: _skills.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          expectedSalaryLpa: double.tryParse(_expectedSalary.text.trim()) ?? 0,
          noticePeriod: _noticePeriod.text.trim(),
          about: _about.text.trim(),
          currentCompany: _currentCompany.text.trim(),
          currentSalaryLpa: double.tryParse(_currentSalary.text.trim()) ?? 0,
          photoUrl: _photoUrl,
          resumeUrl: _resumeUrl,
          introVideoUrl: _introVideoUrl,
        );
        await CandidateProfileService.instance.save(widget.user.uid, profile);
        if (!mounted) return;
        if (_isEditMode) {
          Navigator.of(context).pop(profile);
          return;
        }
        await AuthService.instance.markCandidateProfileComplete();
        if (!mounted) return;
        _backToAuthGate();
      }
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompleteProfileScreen: save failed');
      _showMessage('Something went wrong saving your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    AppToast.message(message, isError: isError);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isEditMode)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(child: _buildHeaderText()),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _isRecruiter ? _recruiterFields() : _candidateFields(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isEditMode ? 'Edit your profile' : 'One last step',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          _isRecruiter
              ? 'Finish setting up your recruiter profile'
              : 'Tell us about yourself so recruiters can find you',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  List<Widget> _recruiterFields() {
    return [
      FadeInUp(
        child: TextFormField(
          controller: _designation,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Designation', Icons.badge_outlined),
          validator: designationValidator,
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 40),
        child: TextFormField(
          controller: _recruiterPhone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Phone', Icons.phone_outlined),
          validator: phoneValidator,
        ),
      ),
      const SizedBox(height: 26),
      FadeInUp(delay: const Duration(milliseconds: 80), child: _submitButton()),
    ];
  }

  List<Widget> _candidateFields() {
    return [
      FadeInUp(
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _age,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Age', Icons.cake_outlined),
                validator: requiredValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _desiredRole,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Desired role', Icons.work_outline_rounded),
                validator: requiredValidator,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 30),
        child: TextFormField(
          controller: _qualification,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Qualification', Icons.school_outlined),
          validator: requiredValidator,
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 60),
        child: TextFormField(
          controller: _experience,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Experience (e.g. 3 years)', Icons.timeline_rounded),
          validator: requiredValidator,
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 90),
        child: TextFormField(
          controller: _location,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Location', Icons.location_on_outlined),
          validator: requiredValidator,
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 120),
        child: TextFormField(
          controller: _skills,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('Skills (comma separated)', Icons.auto_awesome_outlined),
          validator: requiredValidator,
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 150),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _expectedSalary,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Expected CTC (LPA)', Icons.payments_outlined),
                validator: requiredValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _noticePeriod,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Notice period', Icons.event_available_outlined),
                validator: requiredValidator,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 180),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _currentCompany,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Current company', Icons.apartment_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _currentSalary,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: authFieldDecoration('Current CTC (LPA)', Icons.account_balance_wallet_outlined),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 210),
        child: TextFormField(
          controller: _about,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: authFieldDecoration('About you', Icons.notes_rounded),
        ),
      ),
      const SizedBox(height: 22),
      FadeInUp(delay: const Duration(milliseconds: 240), child: _buildMediaSection()),
      const SizedBox(height: 26),
      FadeInUp(delay: const Duration(milliseconds: 280), child: _submitButton()),
    ];
  }

  Widget _buildMediaSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.perm_media_outlined, size: 16, color: AppColors.accentAlt),
              SizedBox(width: 8),
              Text('Photo, resume & intro video', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.accentAlt)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Recruiters double-tap your card for the resume and swipe for the intro video -- upload them here.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 14),
          _MediaUploadRow(
            icon: Icons.person_outline_rounded,
            label: 'Profile photo',
            hint: 'Max ${_formatBytes(_maxPhotoBytes)}',
            hasFile: _photoUrl.isNotEmpty,
            uploading: _uploadingSlot == 'photo',
            onTap: () => _pickAndUpload(
              slot: 'photo',
              fileType: FileType.image,
              maxBytes: _maxPhotoBytes,
              upload: (file) => CandidateProfileService.instance.uploadPhoto(widget.user.uid, file),
              onUploaded: (url) => _photoUrl = url,
            ),
          ),
          const SizedBox(height: 10),
          _MediaUploadRow(
            icon: Icons.description_outlined,
            label: 'Resume (PDF)',
            hint: 'Max ${_formatBytes(_maxResumeBytes)}',
            hasFile: _resumeUrl.isNotEmpty,
            uploading: _uploadingSlot == 'resume',
            onTap: () => _pickAndUpload(
              slot: 'resume',
              fileType: FileType.custom,
              maxBytes: _maxResumeBytes,
              allowedExtensions: const ['pdf'],
              upload: (file) => CandidateProfileService.instance.uploadResume(widget.user.uid, file),
              onUploaded: (url) => _resumeUrl = url,
            ),
          ),
          const SizedBox(height: 10),
          _MediaUploadRow(
            icon: Icons.videocam_outlined,
            label: 'Intro video',
            hint: 'Max ${_formatBytes(_maxVideoBytes)}',
            hasFile: _introVideoUrl.isNotEmpty,
            uploading: _uploadingSlot == 'intro_video',
            onTap: () => _pickAndUpload(
              slot: 'intro_video',
              fileType: FileType.video,
              maxBytes: _maxVideoBytes,
              upload: (file) => CandidateProfileService.instance.uploadIntroVideo(widget.user.uid, file),
              onUploaded: (url) => _introVideoUrl = url,
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    return FilledButton(
      onPressed: _loading ? null : _submit,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: _loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          : Text(_isEditMode ? 'Save changes' : 'Continue'),
    );
  }
}

class _MediaUploadRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool hasFile;
  final bool uploading;
  final VoidCallback onTap;

  const _MediaUploadRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.hasFile,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: uploading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accentAlt),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                      hasFile ? 'Uploaded · $hint' : 'Not uploaded · $hint',
                      style: TextStyle(color: hasFile ? AppColors.like : AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accentAlt))
              else
                Icon(hasFile ? Icons.refresh_rounded : Icons.upload_rounded, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
