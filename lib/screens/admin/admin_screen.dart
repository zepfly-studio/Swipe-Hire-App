import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// The government portal where a GSTIN is looked up before approving.
const String kGstSearchUrl = 'https://services.gst.gov.in/services/searchtp';

/// Admin (spec C14): the only job is reviewing GSTIN verification requests.
class AdminScreen extends StatefulWidget {
  /// For tests; the app uses [AdminService.instance].
  final AdminService? service;

  /// Opens a URL; for tests (defaults to the external browser).
  final Future<bool> Function(Uri uri)? openUrl;

  const AdminScreen({super.key, this.service, this.openUrl});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<AdminVerificationRequest> _rows = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  AdminService get _service => widget.service ?? AdminService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.pendingVerifications();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AdminScreen: load failed');
      if (!mounted) return;
      setState(() {
        _error = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _decide(AdminVerificationRequest row, {required bool approve}) async {
    if (_busy.contains(row.id)) return;
    setState(() => _busy.add(row.id));
    try {
      await _service.decide(row.id, approve: approve);
      if (!mounted) return;
      setState(() {
        _busy.remove(row.id);
        _rows = _rows.where((r) => r.id != row.id).toList();
      });
      AppToast.success(approve ? '${row.companyName} verified' : '${row.companyName} rejected');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy.remove(row.id);
        // Already decided elsewhere: the row no longer exists.
        if (e.statusCode == 404) _rows = _rows.where((r) => r.id != row.id).toList();
      });
      AppToast.error(e.message);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AdminScreen: decision failed');
      if (!mounted) return;
      setState(() => _busy.remove(row.id));
      AppToast.error('Could not save your decision', description: 'Check your connection and try again.');
    }
  }

  Future<void> _checkGstin() async {
    final uri = Uri.parse(kGstSearchUrl);
    try {
      final open = widget.openUrl ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));
      if (!await open(uri) && mounted) AppToast.error('Could not open the GST portal');
    } catch (_) {
      if (mounted) AppToast.error('Could not open the GST portal');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(title: const Text('Admin · company verification')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const Text(
                      'Check each GSTIN on the government portal before approving.',
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      _Notice(
                        icon: Icons.cloud_off_rounded,
                        text: _error!,
                        action: TextButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          child: const Text('Try again'),
                        ),
                      )
                    else if (_rows.isEmpty)
                      const _Notice(icon: Icons.check_circle_outline_rounded, text: 'No pending requests 🎉')
                    else
                      for (final row in _rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RequestCard(
                            row: row,
                            busy: _busy.contains(row.id),
                            onCheck: _checkGstin,
                            onReject: () => _decide(row, approve: false),
                            onApprove: () => _decide(row, approve: true),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final AdminVerificationRequest row;
  final bool busy;
  final VoidCallback onCheck;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  const _RequestCard({
    required this.row,
    required this.busy,
    required this.onCheck,
    required this.onReject,
    required this.onApprove,
  });

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
          Text(row.companyName, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          if (row.detailLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.detailLine,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              row.gstin.isEmpty ? '-' : row.gstin,
              key: Key('gstin-${row.id}'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onCheck,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Check GSTIN'),
              ),
              OutlinedButton.icon(
                key: Key('reject-${row.id}'),
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.reject,
                  side: const BorderSide(color: AppColors.reject),
                ),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Reject'),
              ),
              FilledButton.icon(
                key: Key('approve-${row.id}'),
                onPressed: busy ? null : onApprove,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
