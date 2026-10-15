import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/app_user.dart';
import '../../../models/candidate_profile.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../services/candidate_profile_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/error_reporter.dart';
import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_gate.dart';
import 'onboarding_form.dart';
import 'onboarding_media.dart';
import 'step_details.dart';
import 'step_resume.dart';
import 'step_video.dart';
import 'step_work.dart';

/// The 4-step candidate onboarding (and, with [existingProfile], the
/// "Edit profile" flow): Details -> Work & skills -> Resume -> Intro video.
///
/// Steps 0-1 are kept as a local draft. Nothing is sent to our backend until
/// the last step's "Save": then the whole profile is PUT (with the resume and
/// video URLs the media uploads produced) and the account is marked complete.
/// In edit mode the screen pops with the saved [CandidateProfile].
class CandidateOnboardingScreen extends StatefulWidget {
  final AppUser user;

  /// Non-null = edit mode (starts at step 0 with these values).
  final CandidateProfile? existingProfile;

  const CandidateOnboardingScreen({
    super.key,
    required this.user,
    this.existingProfile,
  });

  @override
  State<CandidateOnboardingScreen> createState() =>
      _CandidateOnboardingScreenState();
}

class _CandidateOnboardingScreenState extends State<CandidateOnboardingScreen> {
  bool get _edit => widget.existingProfile != null;

  bool _loading = true;
  int _step = 0;
  bool _forward = true;
  int _revision = 0; // bumps when auto-fill rewrites step 0-1 values
  bool _done = false;
  bool _saving = false;
  bool _recording = false;

  final OnboardingForm _form = OnboardingForm();
  CandidateProfile _base = const CandidateProfile();
  Map<String, String> _errors = {};
  Timer? _draftTimer;

  // Resume
  String _resumeUrl = '';
  PickedFile? _resumePicked;
  String? _resumeError;
  bool _resumeUploading = false;
  double _resumeProgress = 0;

  // Auto-fill box
  AutofillPhase _autofillPhase = AutofillPhase.idle;
  double _autofillProgress = 0;
  int _autofillFilled = 0;
  String? _autofillError;

  // Video
  String _videoUrl = '';
  PickedFile? _videoPicked;
  String? _videoError;
  bool _videoUploading = false;
  double _videoProgress = 0;

  CandidateProfile? _saved;

  String get _uid => widget.user.uid;

  @override
  void initState() {
    super.initState();
    TaxonomyService.instance.ensureLoaded();
    _init();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    CandidateProfile? profile = widget.existingProfile;
    if (profile == null) {
      try {
        profile = await CandidateProfileService.instance.fetch(_uid);
      } catch (_) {
        // A first-time candidate has no profile yet; offline is fine too.
      }
    }
    final p = profile ?? const CandidateProfile();
    _base = p;
    final fresh = OnboardingForm.fromProfile(p);
    _form.applyDraft(fresh.toDraft());
    _resumeUrl = p.resumeUrl;
    _videoUrl = p.introVideoUrl;

    var start = 0;
    final draft = await OnboardingDraftStore.load(_uid, edit: _edit);
    if (draft != null) {
      _form.applyDraft(draft);
      final s = draft['_step'];
      if (s is int && s >= 0 && s <= 1) start = s;
    } else if (!_edit &&
        _form.validateDetails().isEmpty &&
        _form.validateWork().isEmpty) {
      // Details were saved earlier: pick up at the first missing media step.
      start = _resumeUrl.isEmpty ? 2 : 3;
    }
    if (!mounted) return;
    setState(() {
      _step = start;
      _loading = false;
    });
  }

  // -- draft ------------------------------------------------------------------

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _saveDraftNow);
  }

  void _saveDraftNow() {
    OnboardingDraftStore.save(_uid, {
      ..._form.toDraft(),
      '_step': _step.clamp(0, 1),
    }, edit: _edit);
  }

  void _onEdited(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
    _scheduleDraft();
  }

  // -- navigation ---------------------------------------------------------------

  void _goTo(int step, {bool forward = true}) {
    setState(() {
      _forward = forward;
      _step = step;
    });
    _saveDraftNow();
  }

  void _back() {
    if (_step > 0 && !_busy) _goTo(_step - 1, forward: false);
  }

  bool get _busy =>
      _saving ||
      _resumeUploading ||
      _videoUploading ||
      _recording ||
      _autofillPhase == AutofillPhase.uploading ||
      _autofillPhase == AutofillPhase.reading;

  Future<void> _logout() async {
    await OnboardingDraftStore.clear(_uid);
    await AuthService.instance.signOut();
  }

  Future<void> _cancelEdit() async {
    await OnboardingDraftStore.clear(_uid);
    if (mounted) Navigator.of(context).pop();
  }

  // -- resume auto-fill (step 0) ---------------------------------------------------

  Future<void> _pickForAutofill() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null || !mounted) return;
    final path = file.path;
    final size = file.lengthSync() ?? await file.length() ?? 0;
    final problem = path == null
        ? 'Please choose a PDF file'
        : validateResumeFile(file.name, size);
    if (problem != null) {
      setState(() => _autofillError = problem);
      return;
    }
    setState(() {
      _autofillError = null;
      _autofillPhase = AutofillPhase.uploading;
      _autofillProgress = 0;
    });

    // Read it for the form AND keep it as the candidate's resume.
    final cloudinary = CloudinaryService.instance.uploadResumeFile(
      path!,
      name: file.name,
    );
    try {
      final result = await CandidateProfileService.instance.autofillFromResume(
        path,
        filename: file.name,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _autofillProgress = p;
            if (p >= 1) _autofillPhase = AutofillPhase.reading;
          });
        },
      );
      if (!mounted) return;
      final filled = _form.applyAutofill(
        result.fields,
        skillOptions: TaxonomyService.instance.current.skills,
      );
      String? url;
      try {
        url = await cloudinary;
      } catch (e, st) {
        ErrorReporter.report(
          e,
          st,
          reason: 'Onboarding: resume upload after autofill failed',
        );
      }
      if (!mounted) return;
      setState(() {
        _revision++;
        _autofillFilled = filled;
        _autofillPhase = url != null ? AutofillPhase.done : AutofillPhase.idle;
        if (url != null) {
          _resumeUrl = url;
          _resumePicked = null;
        } else {
          // Fields are filled; the candidate can still upload it on step 3.
          _resumePicked = PickedFile(path: path, name: file.name, size: size);
        }
      });
      _saveDraftNow();
      if (filled > 0) {
        AppToast.success(
          'Filled $filled field${filled == 1 ? '' : 's'} from your resume. Please check them.',
        );
      } else {
        AppToast.info(
          "Resume saved. We couldn't read new details from it, please fill the form.",
        );
      }
    } on ApiException catch (e) {
      // Drain the parallel upload so it cannot raise an unhandled error.
      unawaited(cloudinary.then((_) {}, onError: (_) {}));
      if (!mounted) return;
      setState(() {
        _autofillPhase = AutofillPhase.idle;
        _autofillError = e.message;
      });
    } catch (e, st) {
      unawaited(cloudinary.then((_) {}, onError: (_) {}));
      ErrorReporter.report(e, st, reason: 'Onboarding: resume autofill failed');
      if (!mounted) return;
      setState(() {
        _autofillPhase = AutofillPhase.idle;
        _autofillError =
            'We could not read your resume. Please fill the form yourself.';
      });
    }
  }

  // -- resume (step 2) ---------------------------------------------------------------

  Future<void> _pickResume() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null || !mounted) return;
    final path = file.path;
    final size = file.lengthSync() ?? await file.length() ?? 0;
    final problem = path == null
        ? 'Please choose a PDF file'
        : validateResumeFile(file.name, size);
    setState(() {
      if (problem != null) {
        _resumeError = problem;
      } else {
        _resumeError = null;
        _resumePicked = PickedFile(path: path!, name: file.name, size: size);
      }
    });
  }

  Future<void> _continueFromResume() async {
    final picked = _resumePicked;
    if (picked == null) {
      if (_resumeUrl.isEmpty) {
        setState(() => _resumeError = 'Please choose your resume');
        return;
      }
      _goTo(3);
      return;
    }
    setState(() {
      _resumeUploading = true;
      _resumeProgress = 0;
      _resumeError = null;
    });
    try {
      final url = await CloudinaryService.instance.uploadResumeFile(
        picked.path,
        name: picked.name,
        onProgress: (p) {
          if (mounted) setState(() => _resumeProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _resumeUrl = url;
        _resumePicked = null;
        _resumeUploading = false;
      });
      _goTo(3);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'Onboarding: resume upload failed');
      if (!mounted) return;
      setState(() {
        _resumeUploading = false;
        _resumeError = e is StateError
            ? e.message
            : 'Upload failed. Please check your connection and try again.';
      });
    }
  }

  // -- final save ----------------------------------------------------------------------

  Future<void> _finish() async {
    if (_saving) return;
    if (_videoPicked == null && _videoUrl.isEmpty) {
      setState(() => _videoError = 'Please record or upload your intro video');
      return;
    }
    // The earlier steps may have been skipped via a draft; check them again.
    final early = {..._form.validateDetails(), ..._form.validateWork()};
    if (early.isNotEmpty) {
      _showErrors(early);
      return;
    }
    setState(() {
      _saving = true;
      _videoError = null;
    });
    try {
      var videoUrl = _videoUrl;
      final clip = _videoPicked;
      if (clip != null) {
        setState(() {
          _videoUploading = true;
          _videoProgress = 0;
        });
        videoUrl = await CloudinaryService.instance.uploadIntroVideoFile(
          clip.path,
          name: clip.name,
          onProgress: (p) {
            if (mounted) setState(() => _videoProgress = p);
          },
        );
        if (!mounted) return;
        setState(() {
          _videoUrl = videoUrl;
          _videoPicked = null;
          _videoUploading = false;
        });
      }
      final profile = _form.toProfile(
        base: _base,
        resumeUrl: _resumeUrl,
        introVideoUrl: videoUrl,
      );
      final saved = await CandidateProfileService.instance.save(_uid, profile);
      if (!_edit) await AuthService.instance.markCandidateProfileComplete();
      await OnboardingDraftStore.clear(_uid);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _saving = false;
        _done = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _videoUploading = false;
      });
      final field = e.body['field'];
      if (field is String && field.isNotEmpty) {
        _showErrors({canonicalField(field): e.message});
      } else {
        AppToast.error('Could not save your profile', description: e.message);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'Onboarding: save failed');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _videoUploading = false;
        if (_videoPicked != null) {
          _videoError = e is StateError
              ? e.message
              : 'Upload failed. Please check your connection and try again.';
        }
      });
      if (_videoPicked == null) {
        AppToast.error(
          'Something went wrong saving your profile',
          description: 'Please try again.',
        );
      }
    }
  }

  /// Shows [errors] under their inputs and jumps to the earliest step with one.
  void _showErrors(Map<String, String> errors) {
    final steps = errors.keys.map(stepForField).toList()..sort();
    setState(() {
      _errors = errors;
      if (errors.containsKey('resumeUrl')) _resumeError = errors['resumeUrl'];
      if (errors.containsKey('introVideoUrl')) {
        _videoError = errors['introVideoUrl'];
      }
    });
    if (steps.first != _step) _goTo(steps.first, forward: steps.first > _step);
    if (steps.first <= 1) {
      AppToast.warning(
        'Some details need fixing',
        description: errors.values.first,
      );
    }
  }

  void _next() {
    if (_busy) return;
    switch (_step) {
      case 0:
        final e = _form.validateDetails();
        if (e.isNotEmpty) {
          setState(() => _errors = e);
          return;
        }
        setState(() => _errors = {});
        _goTo(1);
      case 1:
        final e = _form.validateWork();
        if (e.isNotEmpty) {
          setState(() => _errors = e);
          return;
        }
        setState(() => _errors = {});
        _goTo(2);
      case 2:
        _continueFromResume();
      default:
        _finish();
    }
  }

  // -- UI ---------------------------------------------------------------------------------

  void _leaveAfterDone() {
    if (_edit) {
      Navigator.of(context).pop(_saved);
    } else {
      // A fresh AuthGate re-reads the (now complete) profile and routes home.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.user.name.trim().split(RegExp(r'\s+')).first;
    return PopScope(
      canPop: _edit && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0 && !_busy && !_done) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgTop,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _done
              ? OnboardingDone(isEdit: _edit, onContinue: _leaveAfterDone)
              : Column(
                  children: [
                    _header(first),
                    Expanded(child: _stepCard()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header(String firstName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GlideRecruit',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Welcome, $firstName',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (_edit)
            TextButton.icon(
              onPressed: _busy ? null : _cancelEdit,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
            )
          else
            TextButton(
              onPressed: _busy ? null : _logout,
              child: const Text('Log out'),
            ),
        ],
      ),
    );
  }

  Widget _stepCard() {
    final (title, subtitle) = kStepTexts[_step];
    final percent = (_step + 1) * 25;
    final lastStep = _step == 3;
    String mainLabel;
    if (_step < 2) {
      mainLabel = 'Continue';
    } else if (_step == 2) {
      mainLabel = _resumePicked != null ? 'Upload & continue' : 'Continue';
    } else {
      mainLabel = _videoPicked != null
          ? 'Upload & finish'
          : 'Keep current & finish';
      if (_videoPicked == null && _videoUrl.isEmpty) {
        mainLabel = 'Upload & finish';
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Step ${_step + 1} of 4',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceAlt,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey('step-$_step');
              final dx = (_forward ? 1.0 : -1.0) * (incoming ? 1 : -1) * 0.12;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(dx, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: SingleChildScrollView(
              key: ValueKey('step-$_step'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: _stepBody(),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (_step > 0) ...[
                SizedBox(
                  width: 54,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _back,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _saving || _resumeUploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : Text(
                          lastStep ? mainLabel : '$mainLabel →',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return StepDetails(
          key: ValueKey('details-$_revision'),
          form: _form,
          errors: _errors,
          onEdited: _onEdited,
          showAutofill:
              !_edit &&
              (_resumeUrl.isEmpty || _autofillPhase != AutofillPhase.idle),
          autofillPhase: _autofillPhase,
          autofillProgress: _autofillProgress,
          autofillFilled: _autofillFilled,
          autofillError: _autofillError,
          onPickResume: _pickForAutofill,
        );
      case 1:
        return StepWork(
          key: ValueKey('work-$_revision'),
          form: _form,
          errors: _errors,
          onEdited: _onEdited,
        );
      case 2:
        return StepResume(
          existingUrl: _resumeUrl,
          picked: _resumePicked,
          error: _resumeError,
          uploading: _resumeUploading,
          progress: _resumeProgress,
          onPick: _pickResume,
          onKeepCurrent: () => setState(() {
            _resumePicked = null;
            _resumeError = null;
          }),
        );
      default:
        return StepVideo(
          existingUrl: _videoUrl,
          picked: _videoPicked,
          error: _videoError,
          uploading: _videoUploading,
          progress: _videoProgress,
          onPicked: (f) => setState(() {
            _videoPicked = f;
            _videoError = null;
          }),
          onRecordingChanged: (v) => setState(() => _recording = v),
        );
    }
  }
}

/// "You're live!" -- shown after a successful save.
class OnboardingDone extends StatelessWidget {
  final bool isEdit;
  final VoidCallback onContinue;
  const OnboardingDone({
    super.key,
    required this.isEdit,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 46,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              isEdit ? 'Profile updated!' : "You're live!",
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              "Companies can now discover your profile. We'll show you here when someone shortlists you.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
              child: const Text(
                'Go to my dashboard',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
