import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/search_rank.dart';
import 'form_blocks.dart';

/// Free text with a suggestion list underneath (website "Autocomplete").
/// The list opens on focus or typing, shows at most [maxSuggestions] matches
/// ranked by [rankSuggestions], and closes once the text exactly matches an
/// option. Matching word prefixes are drawn in bold.
///
/// Pass [options] for a plain list, or [suggest] for custom ranking
/// (see [LocationField]).
class AutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> options;
  final List<String> Function(String query)? suggest;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final int maxSuggestions;
  final IconData? suggestionIcon;
  final int? maxLength;
  final TextInputAction? textInputAction;

  const AutocompleteField({
    super.key,
    required this.controller,
    this.options = const [],
    this.suggest,
    this.hintText,
    this.onChanged,
    this.hasError = false,
    this.maxSuggestions = 10,
    this.suggestionIcon,
    this.maxLength,
    this.textInputAction,
  });

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AutocompleteField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<String> get _suggestions {
    if (!_focus.hasFocus) return const [];
    final q = widget.controller.text;
    final all = widget.suggest != null
        ? widget.suggest!(q)
        : rankSuggestions(q, widget.options, max: widget.maxSuggestions);
    final shown = all.take(widget.maxSuggestions).toList();
    // Closed once the value exactly matches an option.
    final exact = q.trim().toLowerCase();
    if (exact.isNotEmpty && shown.any((s) => s.toLowerCase() == exact)) {
      return const [];
    }
    return shown;
  }

  void _pick(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            maxLength: widget.maxLength,
            textInputAction: widget.textInputAction ?? TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(
              hintText: widget.hintText,
              hasError: widget.hasError,
            ),
            onChanged: widget.onChanged,
            scrollPadding: const EdgeInsets.only(bottom: 280),
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
                    for (final s in suggestions)
                      InkWell(
                        onTap: () => _pick(s),
                        child: Padding(
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
                                  text: s,
                                  query: widget.controller.text,
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

/// [text] with the part each typed word matches in bold.
class HighlightedMatch extends StatelessWidget {
  final String text;
  final String query;
  const HighlightedMatch({super.key, required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) {
      return Text(text, style: base, overflow: TextOverflow.ellipsis);
    }

    // Bold the leading characters of every word that starts with a term.
    final bold = List<bool>.filled(text.length, false);
    final lower = text.toLowerCase();
    for (final m in RegExp(r'[^\s,()/-]+').allMatches(lower)) {
      for (final t in terms) {
        if (m.group(0)!.startsWith(t)) {
          for (var i = m.start; i < m.start + t.length; i++) {
            bold[i] = true;
          }
          break;
        }
      }
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      var j = i;
      while (j < text.length && bold[j] == bold[i]) {
        j++;
      }
      spans.add(
        TextSpan(
          text: text.substring(i, j),
          style: bold[i] ? const TextStyle(fontWeight: FontWeight.w800) : null,
        ),
      );
      i = j;
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      overflow: TextOverflow.ellipsis,
    );
  }
}
