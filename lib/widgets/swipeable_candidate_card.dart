import 'dart:math';
import 'package:flutter/material.dart';
import '../models/candidate.dart';
import '../theme/app_theme.dart';
import 'candidate_card_face.dart';

enum SwipeDirection { left, right }

class SwipeableCandidateCard extends StatefulWidget {
  final Candidate candidate;
  final bool isTopCard;

  /// Right drag = skip to next candidate (no save). Left drag = pass/reject.
  final ValueChanged<SwipeDirection> onSwiped;
  final VoidCallback onSwipeDown;
  final VoidCallback onDoubleTap;

  /// Tapping the card's Wishlist button -- the only way to actually save a
  /// candidate to the shortlist.
  final VoidCallback onWishlistTap;

  const SwipeableCandidateCard({
    super.key,
    required this.candidate,
    required this.isTopCard,
    required this.onSwiped,
    required this.onSwipeDown,
    required this.onDoubleTap,
    required this.onWishlistTap,
  });

  @override
  State<SwipeableCandidateCard> createState() =>
      _SwipeableCandidateCardState();
}

class _SwipeableCandidateCardState extends State<SwipeableCandidateCard>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late AnimationController _controller;
  Animation<Offset>? _animation;
  bool _settling = false;

  static const double _horizontalThreshold = 110;
  static const double _downThreshold = 130;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.isTopCard || _settling) return;
    _controller.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isTopCard || _settling) return;
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.isTopCard || _settling) return;

    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    if (dx.abs() > dy.abs() && dx.abs() > _horizontalThreshold) {
      final direction = dx > 0 ? SwipeDirection.right : SwipeDirection.left;
      _flyOut(direction);
    } else if (dy.abs() > _downThreshold && dy.abs() > dx.abs()) {
      _triggerVideoIntro();
    } else {
      _springBack();
    }
  }

  void _flyOut(SwipeDirection direction, {VoidCallback? onComplete}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final endX = direction == SwipeDirection.right
        ? screenWidth * 1.6
        : -screenWidth * 1.6;
    final end = Offset(endX, _dragOffset.dy + (direction == SwipeDirection.right ? -40 : 40));

    setState(() => _settling = true);
    _animation = Tween<Offset>(begin: _dragOffset, end: end).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() => _dragOffset = _animation!.value);
      });

    _controller.forward(from: 0).whenComplete(() {
      if (onComplete != null) {
        onComplete();
      } else {
        widget.onSwiped(direction);
      }
    });
  }

  void _triggerVideoIntro() {
    widget.onSwipeDown();
    _springBack();
  }

  void _springBack() {
    setState(() => _settling = true);
    _animation = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    )..addListener(() {
        setState(() => _dragOffset = _animation!.value);
      });

    _controller
      ..duration = const Duration(milliseconds: 500)
      ..forward(from: 0).whenComplete(() {
        setState(() => _settling = false);
      });
  }

  @override
  Widget build(BuildContext context) {
    final angle = (_dragOffset.dx / 300).clamp(-0.5, 0.5) * (pi / 10);
    final likeOpacity = (_dragOffset.dx / _horizontalThreshold).clamp(0.0, 1.0);
    final nopeOpacity = (-_dragOffset.dx / _horizontalThreshold).clamp(0.0, 1.0);
    final verticalOpacity = (_dragOffset.dy.abs() / _downThreshold).clamp(0.0, 1.0);
    final isDraggingUp = _dragOffset.dy < 0;

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onDoubleTap: widget.isTopCard ? widget.onDoubleTap : null,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            children: [
              CandidateCardFace(
                candidate: widget.candidate,
                onWishlistTap: widget.isTopCard
                    ? () => _flyOut(SwipeDirection.right, onComplete: widget.onWishlistTap)
                    : null,
                onWatchIntro: widget.isTopCard ? widget.onSwipeDown : null,
                onViewResume: widget.isTopCard ? widget.onDoubleTap : null,
              ),
              if (likeOpacity > 0)
                Positioned(
                  top: 40,
                  left: 24,
                  child: _StampBadge(
                    label: 'NEXT ▸',
                    color: AppColors.accentAlt,
                    opacity: likeOpacity,
                    angle: -0.3,
                  ),
                ),
              if (nopeOpacity > 0)
                Positioned(
                  top: 40,
                  right: 24,
                  child: _StampBadge(
                    label: 'PASS',
                    color: AppColors.reject,
                    opacity: nopeOpacity,
                    angle: 0.3,
                  ),
                ),
              if (verticalOpacity > 0)
                Positioned(
                  top: isDraggingUp ? 90 : null,
                  bottom: isDraggingUp ? null : 110,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _StampBadge(
                      label: isDraggingUp ? 'VIEW INTRO ↑' : 'VIEW INTRO ↓',
                      color: AppColors.accentAlt,
                      opacity: verticalOpacity,
                      angle: 0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StampBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  final double angle;

  const _StampBadge({
    required this.label,
    required this.color,
    required this.opacity,
    required this.angle,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(12),
            color: color.withValues(alpha: 0.12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
