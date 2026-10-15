import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/api_client.dart';
import '../../../services/error_reporter.dart';
import '../../../services/hiring_service.dart';
import '../../../services/verification_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/form_blocks.dart';

/// "Get verified" (spec C9): verify with the work email (instant) or with a
/// GSTIN (reviewed by our team). Pull down to refresh the status.
class VerifyCompanyScreen extends StatefulWidget {
  /// Both are for tests; the app uses the defaults.
  final VerificationService? service;

  /// Re-reads the company after a change. Defaults to
  /// `HiringService.instance.fetchCompany()` so the badge updates everywhere.
  final Future<void> Function()? refreshCompany;

  const VerifyCompanyScreen({super.key, this.service, this.refreshCompany});

  @override
  State<VerifyCompanyScreen> createState() => _VerifyCompanyScreenState();
}

class _VerifyCompanyScreenState extends State<VerifyCompanyScreen> {
  final _code = TextEditingController();
  final _gstin = TextEditingController();

  VerificationInfo? _info;
  bool _loading = true;
  String? _loadError;

  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String _sentTo = '';
  String _devCode = '';
  String? _emailError;

  bool _submitting = false;
  String? _gstError;

  VerificationService get _service => widget.service ?? VerificationService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadError = null;
        _loading = false;
        if (_gstin.text.isEmpty && info.gstin.isNotEmpty) _gstin.text = normalizeGstin(info.gstin);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VerifyCompanyScreen: load failed');
      if (!mounted) return;
      setState(() {
        _loadError = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  /// Keeps the shared company (header badge, company profile) in step.
  Future<void> _refreshCompany() async {
    try {
      final refresh = widget.refreshCompany;
      if (refresh != null) {
        await refresh();
      } else {
        await HiringService.instance.fetchCompany();
      }
    } catch (_) {
      // The badge catches up the next time the company loads.
    }
  }

  String get _loginEmail => _info?.email ?? '';

  Future<void> _sendCode() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _emailError = null;
    });
    try {
      final sent = await _service.sendEmailCode();
      if (!mounted) return;
      final to = sent.sentTo.isEmpty ? _loginEmail : sent.sentTo;
      setState(() {
        _sending = false;
        _codeSent = true;
        _sentTo = to;
        _devCode = sent.devCode;
        _code.clear();
      });
      AppToast.success('Code sent to $to');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _emailError = e.message;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VerifyCompanyScreen: send code failed');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _emailError = 'Could not send the code. Check your connection and try again.';
      });
    }
  }

  Future<void> _confirmCode() async {
    final code = _code.text;
    if (_verifying || !isCompleteEmailCode(code)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _emailError = null;
    });
    try {
      final info = await _service.confirmEmailCode(code, current: _info);
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _info = info;
        _codeSent = false;
        _devCode = '';
      });
      AppToast.success('Your company is verified');
      await _refreshCompany();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _emailError = e.message;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VerifyCompanyScreen: confirm code failed');
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _emailError = 'Could not verify the code. Check your connection and try again.';
      });
    }
  }

  Future<void> _submitGstin() async {
    if (_submitting) return;
    final value = normalizeGstin(_gstin.text);
    if (!gstinHasFullLength(value)) return;
    if (!isValidGstin(value)) {
      setState(() => _gstError = kInvalidGstinMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _gstError = null;
    });
    try {
      final info = await _service.submitGstin(value, current: _info);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _info = info;
      });
      AppToast.success('Submitted! We will review it shortly.');
      await _refreshCompany();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _gstError = e.message;
      });
      // "Already verified": pick up the real status.
      if (e.statusCode == 409) _load();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VerifyCompanyScreen: GSTIN submit failed');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _gstError = 'Could not submit your GSTIN. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(title: const Text('Get verified')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final info = _info;
    if (info == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Could not load your verification status.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: info.isVerified ? [_verifiedCard(info)] : _unverifiedChildren(info),
      ),
    );
  }

  // -- verified ---------------------------------------------------------------

  Widget _verifiedCard(VerificationInfo info) {
    final how = switch (info.method) {
      'gst' => 'verified by GSTIN',
      'admin' => 'verified by the GlideRecruit team',
      _ => 'verified by work email',
    };
    return Container(
      key: const Key('verified-card'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.verified_rounded, size: 40, color: AppColors.info),
          ),
          const SizedBox(height: 16),
          const Text('Your company is verified', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Candidates see a blue badge next to your name in chats and interview invites ($how).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }

  // -- not verified -----------------------------------------------------------

  List<Widget> _unverifiedChildren(VerificationInfo info) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.shield_outlined, color: AppColors.info),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Get verified', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text(
                  'A verified badge shows candidates you are a real company. Verified companies get more replies.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (info.isPending) ...[
        _Banner(
          key: const Key('pending-banner'),
          color: AppColors.warning,
          icon: Icons.hourglass_top_rounded,
          text: 'GSTIN ${info.gstin} is under review. You will get a notification once it is approved, '
              'usually within one working day.',
        ),
        const SizedBox(height: 12),
      ],
      if (info.isRejected) ...[
        const _Banner(
          key: Key('rejected-banner'),
          color: AppColors.reject,
          icon: Icons.error_outline_rounded,
          text: 'We could not verify your GSTIN. Please check it, or verify with your work email instead.',
        ),
        const SizedBox(height: 12),
      ],
      _emailCard(info),
      const SizedBox(height: 14),
      _gstCard(info),
    ];
  }

  Widget _emailCard(VerificationInfo info) {
    final website = info.website.isEmpty ? 'not set yet' : info.website;
    final canVerify = isCompleteEmailCode(_code.text) && !_verifying;
    return _MethodCard(
      title: 'Verify with work email · instant',
      children: [
        Text(
          'Your login email (${info.email.isEmpty ? '-' : info.email}) must be on your company '
          "website's domain ($website).",
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        if (!_codeSent)
          FilledButton(
            onPressed: _sending ? null : _sendCode,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _sending ? const _ButtonSpinner() : const Text('Send code to my email'),
          )
        else ...[
          if (_devCode.isNotEmpty) ...[
            _Banner(
              key: const Key('dev-code-banner'),
              color: AppColors.info,
              icon: Icons.bug_report_outlined,
              text: 'Testing mode: your code is $_devCode',
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Enter the 6-digit code sent to ${_sentTo.isEmpty ? info.email : _sentTo}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('email-code-field'),
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: fieldDecoration(hintText: '123456', hasError: _emailError != null),
            onChanged: (_) => setState(() => _emailError = null),
            onSubmitted: (_) => _confirmCode(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_sending || _verifying) ? null : _sendCode,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: _sending ? const _ButtonSpinner(onLight: true) : const Text('Resend'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canVerify ? _confirmCode : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: _verifying ? const _ButtonSpinner() : const Text('Verify'),
                ),
              ),
            ],
          ),
        ],
        if (_emailError != null) ...[
          const SizedBox(height: 10),
          Text(
            _emailError!,
            key: const Key('email-error'),
            style: const TextStyle(color: AppColors.reject, fontSize: 12.5, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _gstCard(VerificationInfo info) {
    final ready = gstinHasFullLength(_gstin.text) && !_submitting;
    return _MethodCard(
      title: 'Verify with GSTIN · reviewed by our team',
      children: [
        const Text(
          'Use this if you sign in with a personal email.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('gstin-field'),
          controller: _gstin,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: const [GstinInputFormatter(), _MaxLength(15)],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1),
          decoration: fieldDecoration(hintText: '22AAAAA0000A1Z5', hasError: _gstError != null),
          onChanged: (_) => setState(() => _gstError = null),
          onSubmitted: (_) => _submitGstin(),
        ),
        if (_gstError != null) ...[
          const SizedBox(height: 8),
          Text(
            _gstError!,
            key: const Key('gstin-error'),
            style: const TextStyle(color: AppColors.reject, fontSize: 12.5, height: 1.35),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ready ? _submitGstin : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _submitting ? const _ButtonSpinner() : Text(info.isPending ? 'Update' : 'Submit'),
        ),
      ],
    );
  }
}

/// 15-character cap that works as a const formatter.
class _MaxLength extends TextInputFormatter {
  final int max;
  const _MaxLength(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    final text = newValue.text.substring(0, max);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _MethodCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _MethodCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({super.key, required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, height: 1.4, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  final bool onLight;
  const _ButtonSpinner({this.onLight = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: onLight ? AppColors.primary : AppColors.onPrimary),
      );
}
