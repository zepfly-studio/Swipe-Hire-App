import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/utils/search_rank.dart';
import 'package:hiring_app/utils/tag_list.dart';

void main() {
  const skills = ['React', 'Node.js', 'Excel', 'Communication'];

  group('addTag', () {
    test('uses the list spelling', () {
      expect(addTag([], 'react', options: skills), ['React']);
      expect(addTag([], 'NODE.JS', options: skills), ['Node.js']);
    });

    test('keeps what was typed when it is not in the list', () {
      expect(addTag([], '  Public speaking ', options: skills), ['Public speaking']);
    });

    test('de-duplicates case-insensitively', () {
      final tags = ['React'];
      expect(identical(addTag(tags, 'REACT', options: skills), tags), isTrue);
      expect(addTag(['Public speaking'], 'public SPEAKING'), ['Public speaking']);
    });

    test('ignores blanks, caps length and count', () {
      expect(addTag([], '   '), isEmpty);
      expect(addTag([], 'x' * 60).single.length, 40);
      final full = List.generate(30, (i) => 'tag$i');
      expect(identical(addTag(full, 'one more'), full), isTrue);
      expect(addTag(['a', 'b'], 'c', max: 2), ['a', 'b']);
    });

    test('addTags splits on commas', () {
      expect(addTags([], 'react, excel,, react', options: skills), ['React', 'Excel']);
    });
  });

  group('search ranking', () {
    const options = ['Java', 'JavaScript', 'Node.js', 'React Native', 'Data Analysis'];

    test('exact > starts-with > word-start > contains', () {
      expect(searchScore('java', 'Java'), 4);
      expect(searchScore('java', 'JavaScript'), 3);
      expect(searchScore('native', 'React Native'), 2);
      expect(searchScore('ript', 'JavaScript'), 1);
      expect(searchScore('zzz', 'Java'), 0);
    });

    test('loose typo match needs 3 letters and the same first letter', () {
      expect(searchScore('jvs', 'JavaScript'), 1);
      expect(searchScore('vs', 'JavaScript'), 0);
      expect(searchScore('nde', 'Node.js'), 1);
    });

    test('ties keep list order and exclusions are skipped', () {
      expect(rankSuggestions('java', options), ['Java', 'JavaScript']);
      expect(rankSuggestions('java', options, exclude: ['java']), ['JavaScript']);
      expect(rankSuggestions('', options, max: 2), ['Java', 'JavaScript']);
    });

    test('locations: prefix matches first, loose only when none', () {
      const cities = ['Jaipur', 'Jodhpur', 'Mumbai', 'Pune', 'Kolkata'];
      const states = ['Jharkhand', 'Jammu and Kashmir', 'Maharashtra'];
      expect(
        rankLocations('j', cities, states),
        ['Jaipur', 'Jodhpur', 'Jharkhand', 'Jammu and Kashmir'],
      );
      // Nothing starts with "mbi", so the looser match applies.
      expect(rankLocations('mbi', cities, states), contains('Mumbai'));
      expect(
        rankLocations('', cities, states, maxCities: 2, maxStates: 1),
        ['Jaipur', 'Jodhpur', 'Jharkhand'],
      );
    });
  });
}
