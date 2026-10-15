import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/candidate.dart';
import '../../services/api_client.dart';
import '../../services/hiring_service.dart';
import '../../theme/app_theme.dart';
import '../messages/pair_nav.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart' show InitialsAvatar;
import '../../widgets/candidate_details.dart';
import '../../widgets/page_transitions.dart';
import '../resume_screen.dart';
import 'plans/plan_cards.dart';

/// Candidates the company saved to look at again (spec C3).
class WishlistScreen extends StatefulWidget {
  final HiringService? service;
  const WishlistScreen({super.key, this.service});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Candidate> _items = [];
  bool _loading = true;
  String? _error;

  /// Contact details learned by shortlisting from this screen.
  final Map<String, ({String email, String phone})> _contact = {};
  final Set<String> _shortlisted = {};

  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchWishlist();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  String _email(Candidate c) => _contact[c.id]?.email ?? c.contactEmail;
  String _phone(Candidate c) => _contact[c.id]?.phone ?? c.contactPhone;
  bool _isShortlisted(Candidate c) =>
      _shortlisted.contains(c.id) || c.hasContact || c.stage.isNotEmpty || c.swipeId.isNotEmpty;

  Future<void> _remove(Candidate c) async {
    try {
      await _service.setWishlisted(c.id, false);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != c.id).toList());
      AppToast.success('Removed from wishlist');
    } on ApiException catch (e) {
      AppToast.error(e.message);
    }
  }

  /// Returns true when the shortlist went through.
  Future<bool> _shortlist(Candidate c) async {
    try {
      final r = await _service.swipe(candidateId: c.id, action: 'right');
      if (r.swipesLeft != null) _service.updateSwipes(r.swipesLeft!);
      if (!mounted) return true;
      setState(() {
        _shortlisted.add(c.id);
        _contact[c.id] = (email: r.contactEmail, phone: r.contactPhone);
      });
      AppToast.success('${c.name.split(' ').first} shortlisted!');
      return true;
    } on ApiException catch (e) {
      final code = e.body['code'];
      if (code == 'NO_SWIPES' || e.statusCode == 402) {
        HiringService.swipesLeft.value = 0;
        if (mounted) showPaywall(context);
      } else if (code == 'SALARY_MISMATCH') {
        AppToast.error(e.message, duration: const Duration(seconds: 6));
      } else if (e.statusCode == 409) {
        // Already swiped for the default job: it is shortlisted already.
        if (mounted) setState(() => _shortlisted.add(c.id));
        AppToast.info('Already shortlisted');
      } else {
        AppToast.error(e.message);
      }
      return false;
    }
  }

  void _message(Candidate c) => PairNav.openChat(context, c.id, isCompany: true);

  Future<void> _open(Candidate c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgTop,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => _CandidateSheet(
        candidate: c,
        email: () => _email(c),
        phone: () => _phone(c),
        shortlisted: () => _isShortlisted(c),
        onRemove: () async {
          Navigator.of(sheetContext).pop();
          await _remove(c);
        },
        onShortlist: () => _shortlist(c),
        onMessage: () {
          Navigator.of(sheetContext).pop();
          _message(c);
        },
        onResume: () => pushSmooth(sheetContext, ResumeScreen(candidate: c)),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_rounded, size: 20, color: AppColors.reject),
            const SizedBox(width: 8),
            const Text('Wishlist'),
            const SizedBox(width: 8),
            if (_items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_items.length}', style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 52, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              const Text(
                'Tap the heart on a candidate card to save them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => PairNav.openSwipe(context),
                child: const Text('Start swiping'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 900 ? 3 : (box.maxWidth >= 600 ? 2 : 1);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 168,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final c = _items[i];
              return _WishlistCard(
                candidate: c,
                shortlisted: _isShortlisted(c),
                email: _email(c),
                onTap: () => _open(c),
                onMessage: () => _message(c),
              );
            },
          );
        },
      ),
    );
  }
}

class _WishlistCard extends StatelessWidget {
  final Candidate candidate;
  final bool shortlisted;
  final String email;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  const _WishlistCard({
    required this.candidate,
    required this.shortlisted,
    required this.email,
    required this.onTap,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final exp = candidateExperienceChip(c);
    final extra = c.skills.length > 4 ? c.skills.length - 4 : 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(candidate: c, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                            ),
                            if (shortlisted) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, size: 16, color: AppColors.like),
                            ],
                          ],
                        ),
                        Text(
                          c.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (shortlisted)
                    IconButton(
                      tooltip: 'Message',
                      onPressed: onMessage,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (c.matchScore != null) MatchBadge(score: c.matchScore!),
                  if (c.location.trim().isNotEmpty && c.location != '-')
                    Text(c.location, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (exp.isNotEmpty) Text('· $exp', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              if (shortlisted && email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.likeText, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              const Spacer(),
              Text(
                c.skills.take(4).join(' · ') + (extra > 0 ? '  +$extra' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Candidate candidate;
  final double size;
  const _Avatar({required this.candidate, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: candidate.photoUrl.isEmpty
            ? InitialsAvatar(name: candidate.name)
            : CachedNetworkImage(
                imageUrl: candidate.photoUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
              ),
      ),
    );
  }
}

class _CandidateSheet extends StatefulWidget {
  final Candidate candidate;
  final String Function() email;
  final String Function() phone;
  final bool Function() shortlisted;
  final Future<void> Function() onRemove;
  final Future<bool> Function() onShortlist;
  final VoidCallback onMessage;
  final VoidCallback onResume;

  const _CandidateSheet({
    required this.candidate,
    required this.email,
    required this.phone,
    required this.shortlisted,
    required this.onRemove,
    required this.onShortlist,
    required this.onMessage,
    required this.onResume,
  });

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  bool _busy = false;

  Future<void> _shortlist() async {
    setState(() => _busy = true);
    await widget.onShortlist();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Copied');
  }

  Widget _contactRow(IconData icon, String value, Uri uri) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.likeText),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => launchUrl(uri),
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.likeText)),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () => _copy(value),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final email = widget.email();
    final phone = widget.phone();
    final shortlisted = widget.shortlisted();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                _Avatar(candidate: c, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(c.role, style: const TextStyle(color: AppColors.textSecondary)),
                      if (c.matchScore != null)
                        Padding(padding: const EdgeInsets.only(top: 4), child: MatchBadge(score: c.matchScore!)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                if (email.isNotEmpty) _contactRow(Icons.mail_outline_rounded, email, Uri.parse('mailto:$email')),
                if (phone.isNotEmpty) _contactRow(Icons.phone_outlined, phone, Uri.parse('tel:$phone')),
                Row(
                  children: [
                    if (shortlisted)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: widget.onMessage,
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text('Message'),
                        ),
                      ),
                    if (shortlisted) const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onResume,
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('View resume'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CandidateDetails(candidate: c),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onRemove,
                    icon: const Icon(Icons.favorite_rounded, size: 18, color: AppColors.reject),
                    label: const Text('Remove'),
                  ),
                ),
                if (!shortlisted) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _shortlist,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                            )
                          : const Text('Shortlist'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
