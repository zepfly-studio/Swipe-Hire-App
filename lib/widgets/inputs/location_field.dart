import 'package:flutter/material.dart';

import '../../services/taxonomy_service.dart';
import '../../utils/search_rank.dart';
import 'autocomplete_field.dart';

/// City input with suggestions from the taxonomy: up to 7 cities and 3
/// states, strict prefix matches first (see [rankLocations]).
class LocationField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final bool hasError;

  const LocationField({
    super.key,
    required this.controller,
    this.hintText,
    this.onChanged,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Taxonomy>(
      valueListenable: TaxonomyService.instance.notifier,
      builder: (context, taxonomy, _) => AutocompleteField(
        controller: controller,
        hintText: hintText,
        onChanged: onChanged,
        hasError: hasError,
        suggestionIcon: Icons.place_outlined,
        maxSuggestions: 10,
        suggest: (q) => rankLocations(q, taxonomy.cities, taxonomy.states),
      ),
    );
  }
}
