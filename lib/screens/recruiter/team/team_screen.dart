import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_client.dart';
import '../../../services/team_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';

/// "Team": who shares this company's jobs, swipes, pipeline and chats. The
/// owner can invite and remove recruiters; members only see the list.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _svc = TeamService.instance;
  final _email = TextEditingController();

  TeamData? _data;
  String? _loadError;
  bool _loading = true;
  bool _sending = false;
  String? _inviteError;

  /// The code of the last invite the server could not email.
  String? _shareCode;
  String? _shareEmail;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await _svc.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadError = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (email.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _inviteError = null;
    });
    try {
      final res = await _svc.invite(email);
      if (!mounted) return;
      _email.clear();
      setState(() {
        _shareCode = res.inviteCode;
        _shareEmail = res.inviteCode == null ? null : email;
      });
      AppToast.success('Invite sent to $email');
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _inviteError = e.message);
    } catch (_) {
      if (mounted) setState(() => _inviteError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _copyCode() async {
    final code = _shareCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    AppToast.message('Code copied');
  }

  Future<void> _removeMember(TeamMember m) async {
    final ok = await _confirm('Remove ${m.displayName} from your team? They will lose access immediately.');
    if (ok != true) return;
    try {
      await _svc.removeMember(m.id);
      AppToast.message('${m.displayName} removed');
      await _load(silent: true);
    } on ApiException catch (e) {
      AppToast.message(e.message, isError: true);
    }
  }

  Future<void> _cancelInvite(TeamInvite i) async {
    try {
      await _svc.cancelInvite(i.id);
      await _load(silent: true);
    } on ApiException catch (e) {
      AppToast.message(e.message, isError: true);
    }
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove', style: TextStyle(color: AppColors.reject)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _data;
    if (data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError ?? 'Could not load your team.', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Row(
            children: [
              Icon(Icons.groups_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Team', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Recruiters on your team share jobs, swipes, pipeline and chats. Up to $kMaxTeamSize people.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (data.isOwner) ...[
            _inviteBox(),
            if (_shareCode != null) ...[const SizedBox(height: 12), _codeCard()],
            const SizedBox(height: 16),
          ],
          _card([
            for (var i = 0; i < data.members.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              _memberRow(data.members[i], canRemove: data.isOwner),
            ],
            for (final inv in data.invites) ...[
              if (data.members.isNotEmpty) const Divider(height: 1, color: AppColors.border),
              _inviteRow(inv, canCancel: data.isOwner),
            ],
          ]),
          if (!data.isOwner) ...[
            const SizedBox(height: 16),
            const Text(
              'Only the account owner can invite or remove people.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      );

  Widget _inviteBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Invite a recruiter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _invite(),
            onChanged: (_) {
              if (_inviteError != null) setState(() => _inviteError = null);
            },
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'colleague@company.com',
              errorText: _inviteError,
              errorMaxLines: 3,
              filled: true,
              fillColor: AppColors.surfaceAlt,
              prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _email.text.trim().isEmpty || _sending ? null : _invite,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                : const Text('Send invite'),
          ),
        ],
      ),
    );
  }

  Widget _codeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share this code with $_shareEmail', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'They open GlideRecruit, choose "Join a team" and enter it.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _shareCode!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Copy code',
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberRow(TeamMember m, {required bool canRemove}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _tile(Text(m.initials, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: m.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    children: [
                      if (m.isYou)
                        const TextSpan(
                          text: ' (you)',
                          style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (m.email.isNotEmpty)
                  Text(m.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _badge(m.isOwner ? 'Owner' : 'Recruiter', owner: m.isOwner),
          if (canRemove && !m.isOwner && !m.isYou)
            IconButton(
              tooltip: 'Remove ${m.displayName}',
              onPressed: () => _removeMember(m),
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.reject, size: 22),
            ),
        ],
      ),
    );
  }

  Widget _inviteRow(TeamInvite i, {required bool canCancel}) {
    return Opacity(
      opacity: 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _tile(const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.email,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Text('Invite pending', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                ],
              ),
            ),
            if (canCancel)
              IconButton(
                tooltip: 'Cancel invite',
                onPressed: () => _cancelInvite(i),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.reject, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Widget child) => Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _badge(String text, {required bool owner}) {
    final color = owner ? AppColors.warning : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
