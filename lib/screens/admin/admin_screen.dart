import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// The government portal where a GSTIN is looked up (only when a company
/// actually submitted one).
const String kGstSearchUrl = 'https://services.gst.gov.in/services/searchtp';

/// Admin: every company, with a one-tap Verify / Remove badge. A GSTIN is not
/// needed; when a company did submit one it is shown with a "Check GSTIN"
/// link and its request can be approved or rejected here too.
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
  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('pending', 'Needs review'),
    ('unverified', 'Not verified'),
    ('verified', 'Verified'),
  ];

  final _search = TextEditingController();
  Timer? _debounce;
  List<AdminCompany> _rows = const [];
  String _status = 'all';
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};
  int _loadGen = 0;

  AdminService get _service => widget.service ?? AdminService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    try {
      final rows = await _service.companies(status: _status, query: _search.text.trim());
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _rows = rows;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AdminScreen: load failed');
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _loading = true;
    });
    _load();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _loading = true);
      _load();
    });
  }

  /// Runs one admin action on a company and then refreshes the list.
  Future<void> _act(AdminCompany row, Future<void> Function() run, String doneMessage) async {
    if (_busy.contains(row.id)) return;
    setState(() => _busy.add(row.id));
    try {
      await run();
      if (!mounted) return;
      setState(() => _busy.remove(row.id));
      AppToast.success(doneMessage);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(row.id));
      AppToast.error(e.message);
      if (e.statusCode == 404) await _load();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AdminScreen: action failed');
      if (!mounted) return;
      setState(() => _busy.remove(row.id));
      AppToast.error('Could not save your decision', description: 'Check your connection and try again.');
    }
  }

  Future<void> _confirmRemove(AdminCompany row) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove the verified badge from ${row.companyName}?'),
        content: const Text('Candidates will stop seeing the badge until the company is verified again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.reject),
            child: const Text('Remove badge'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _act(row, () => _service.setVerified(row.id, verified: false), 'Badge removed from ${row.companyName}');
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
      appBar: AppBar(title: const Text('Admin · companies')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                key: const Key('admin-search'),
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search company, website or owner email',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final (key, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('admin-filter-$key'),
                        label: Text(label),
                        selected: _status == key,
                        onSelected: (_) => _setStatus(key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        children: [
                          const Text(
                            'Verify any company yourself. A GSTIN is not required.',
                            style: TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
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
                            const _Notice(icon: Icons.apartment_rounded, text: 'No companies here yet')
                          else
                            for (final row in _rows)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _CompanyCard(
                                  row: row,
                                  busy: _busy.contains(row.id),
                                  onCheckGstin: _checkGstin,
                                  onVerify: () => _act(
                                    row,
                                    () => _service.setVerified(row.id, verified: true),
                                    '${row.companyName} verified',
                                  ),
                                  onRemoveBadge: () => _confirmRemove(row),
                                  onReject: () => _act(
                                    row,
                                    () => _service.decide(row.id, approve: false),
                                    '${row.companyName} rejected',
                                  ),
                                ),
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

class _StatusPill extends StatelessWidget {
  final AdminCompany row;
  const _StatusPill({required this.row});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.status) {
      'verified' => (row.methodLabel.isEmpty ? 'Verified' : 'Verified ${row.methodLabel}', AppColors.like),
      'pending' => ('Needs review', AppColors.warning),
      'rejected' => ('Rejected', AppColors.reject),
      _ => ('Not verified', AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

final ButtonStyle _compact = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 44),
  padding: const EdgeInsets.symmetric(horizontal: 14),
);

class _CompanyCard extends StatelessWidget {
  final AdminCompany row;
  final bool busy;
  final VoidCallback onCheckGstin;
  final VoidCallback onVerify;
  final VoidCallback onRemoveBadge;
  final VoidCallback onReject;

  const _CompanyCard({
    required this.row,
    required this.busy,
    required this.onCheckGstin,
    required this.onVerify,
    required this.onRemoveBadge,
    required this.onReject,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(row.companyName, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              _StatusPill(row: row),
            ],
          ),
          if (row.detailLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.detailLine,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (row.gstin.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                'GSTIN  ${row.gstin}',
                key: Key('gstin-${row.id}'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (row.gstin.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onCheckGstin,
                  style: _compact,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Check GSTIN'),
                ),
              if (row.status == 'pending')
                OutlinedButton.icon(
                  key: Key('reject-${row.id}'),
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: AppColors.reject,
                    side: const BorderSide(color: AppColors.reject),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                ),
              if (row.verified)
                OutlinedButton.icon(
                  key: Key('unverify-${row.id}'),
                  onPressed: busy ? null : onRemoveBadge,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: AppColors.reject,
                    side: const BorderSide(color: AppColors.reject),
                  ),
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Remove badge'),
                )
              else
                FilledButton.icon(
                  key: Key('verify-${row.id}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: busy ? null : onVerify,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Verify'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
