import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/search_rank.dart';
import '../../utils/tag_list.dart';
import 'autocomplete_field.dart';

/// Chips + free text (website "TagInput").
///
/// - Suggestions come from [options], skipping tags already added.
/// - Enter adds the top suggestion (or the typed text); a comma adds exactly
///   what was typed; leaving the field adds the pending text.
/// - Backspace on an empty input removes the last chip.
/// - De-duplicated case-insensitively; a typed "react" becomes the list's
///   "React". At most [max] tags of [maxLen] characters each.
class TagInput extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> options;
  final int max;
  final int maxLen;
  final String? hintText;
  final bool hasError;
  final IconData? suggestionIcon;

  /// Suggestion source override (locations use their own ranking).
  final List<String> Function(String query, List<String> exclude)? suggest;

  const TagInput({
    super.key,
    required this.tags,
    required this.onChanged,
    this.options = const [],
    this.max = 30,
    this.maxLen = 40,
    this.hintText,
    this.hasError = false,
    this.suggestionIcon,
    this.suggest,
  });

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  // A zero-width sentinel keeps one deletable character in the field, so a
  // soft keyboard's Backspace on "empty" input still produces a change we
  // can turn into "remove the last chip".
  static const _sentinel = '​';

  final TextEditingController _controller = TextEditingController(
    text: _sentinel,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.selection = const TextSelection.collapsed(offset: 1);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _typed => _controller.text.replaceAll(_sentinel, '');

  void _setTyped(String text) {
    final full = '$_sentinel$text';
    _controller.value = TextEditingValue(
      text: full,
      selection: TextSelection.collapsed(offset: full.length),
    );
  }

  void _onFocus() {
    if (!_focus.hasFocus && _typed.trim().isNotEmpty) {
      _commit(_typed);
      _setTyped('');
    }
    if (mounted) setState(() {});
  }

  void _commit(String raw) {
    final next = addTag(
      widget.tags,
      raw,
      options: widget.options,
      max: widget.max,
      maxLen: widget.maxLen,
    );
    if (!identical(next, widget.tags)) widget.onChanged(next);
  }

  List<String> _suggestions() {
    if (!_focus.hasFocus || widget.tags.length >= widget.max) return const [];
    final q = _typed;
    if (widget.suggest != null) {
      return widget.suggest!(q, widget.tags).take(8).toList();
    }
    return rankSuggestions(q, widget.options, max: 8, exclude: widget.tags);
  }

  void _onTextChanged(String value) {
    if (!value.startsWith(_sentinel)) {
      // The sentinel was deleted: Backspace on an empty input.
      if (widget.tags.isNotEmpty) {
        widget.onChanged(widget.tags.sublist(0, widget.tags.length - 1));
      }
      _setTyped(value.replaceAll(_sentinel, ''));
      return;
    }
    final typed = value.substring(1);
    if (typed.contains(',')) {
      final parts = typed.split(',');
      var tags = widget.tags;
      for (final p in parts.sublist(0, parts.length - 1)) {
        tags = addTag(
          tags,
          p,
          options: widget.options,
          max: widget.max,
          maxLen: widget.maxLen,
        );
      }
      if (!identical(tags, widget.tags)) widget.onChanged(tags);
      _setTyped(parts.last);
      return;
    }
    setState(() {});
  }

  void _onSubmitted(String _) {
    final typed = _typed.trim();
    final suggestions = _suggestions();
    if (typed.isEmpty) {
      _setTyped('');
      return;
    }
    // Enter takes the highlighted (top) suggestion when there is one.
    _commit(suggestions.isNotEmpty ? suggestions.first : typed);
    _setTyped('');
    _focus.requestFocus();
  }

  void _removeAt(int i) {
    final next = [...widget.tags]..removeAt(i);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();
    final atLimit = widget.tags.length >= widget.max;
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.hasError
                    ? AppColors.reject
                    : (_focus.hasFocus ? AppColors.primary : AppColors.border),
                width: _focus.hasFocus ? 1.5 : 1,
              ),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < widget.tags.length; i++)
                  _TagChip(label: widget.tags[i], onRemove: () => _removeAt(i)),
                if (!atLimit)
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.words,
                      onChanged: _onTextChanged,
                      onSubmitted: _onSubmitted,
                      scrollPadding: const EdgeInsets.only(bottom: 280),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 2,
                        ),
                        hintText: widget.tags.isEmpty
                            ? widget.hintText
                            : 'Add more…',
                        hintStyle: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    'Maximum ${widget.max} reached',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow(),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    for (var i = 0; i < suggestions.length; i++)
                      InkWell(
                        onTap: () {
                          _commit(suggestions[i]);
                          _setTyped('');
                          _focus.requestFocus();
                        },
                        child: Container(
                          color: i == 0 && _typed.isNotEmpty
                              ? AppColors.primary.withValues(alpha: 0.06)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              if (widget.suggestionIcon != null) ...[
                                Icon(
                                  widget.suggestionIcon,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: HighlightedMatch(
                                  text: suggestions[i],
                                  query: _typed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _TagChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
