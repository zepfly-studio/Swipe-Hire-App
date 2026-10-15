import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/utils/salary.dart';

void main() {
  group('parseLpa', () {
    test('plain LPA values', () {
      expect(parseLpa('6').value, 6);
      expect(parseLpa('4.5').value, 4.5);
      expect(parseLpa('4.5').converted, isFalse);
      expect(parseLpa('4.5').hint, 'In lakh per year, e.g. 4.5');
    });

    test('1000 or more is a yearly rupee amount', () {
      final p = parseLpa('450000');
      expect(p.converted, isTrue);
      expect(p.value, closeTo(4.5, 1e-9));
      expect(p.hint, '= ₹4.5 LPA (₹4,50,000 per year)');
      expect(parseLpa('4,50,000').value, closeTo(4.5, 1e-9));
      expect(parseLpa('1000').converted, isTrue);
    });

    test('invalid input', () {
      expect(parseLpa('abc').valid, isFalse);
      expect(parseLpa('').valid, isFalse);
      expect(parseLpa('-3').valid, isFalse);
      // Above 1000 LPA after conversion.
      expect(parseLpa('200000000').valid, isFalse);
    });
  });

  test('formatInr uses Indian grouping', () {
    expect(formatInr(999), '999');
    expect(formatInr(1000), '1,000');
    expect(formatInr(450000), '4,50,000');
    expect(formatInr(12345678), '1,23,45,678');
  });

  group('validation', () {
    test('minimum is required and must be valid', () {
      expect(validateMinSalary(''), 'Enter the minimum salary you expect');
      expect(validateMinSalary('abc'), 'Enter a valid salary');
      expect(validateMinSalary('0'), 'Enter a valid salary');
      expect(validateMinSalary('6'), isNull);
      expect(validateMinSalary('600000'), isNull);
    });

    test('maximum is optional and must exceed the minimum', () {
      expect(validateMaxSalary('', '6'), isNull);
      expect(validateMaxSalary('x', '6'), 'Enter a valid salary');
      expect(validateMaxSalary('5', '6'), 'Should be more than the minimum');
      expect(validateMaxSalary('6', '6'), 'Should be more than the minimum');
      expect(validateMaxSalary('8', '6'), isNull);
    });

    test('current salary is optional', () {
      expect(validateCurrentSalary(''), isNull);
      expect(validateCurrentSalary('4.5'), isNull);
      expect(validateCurrentSalary('nope'), 'Enter a valid salary');
    });

    test('experience years', () {
      expect(validateExperienceYears(''), 'Enter your experience (0 if fresher)');
      expect(validateExperienceYears('0'), isNull);
      expect(validateExperienceYears('2.5'), isNull);
      expect(validateExperienceYears('51'), 'Enter years between 0 and 50');
      expect(validateExperienceYears('-1'), 'Enter years between 0 and 50');
    });
  });

  test('experience text sent to the server', () {
    expect(experienceTextFor(0), 'Fresher');
    expect(experienceTextFor(3), '3 years');
    expect(experienceTextFor(2.5), '2.5 years');
  });

  test('salary range label', () {
    expect(salaryRangeLabel(6, 8, negotiable: true), '₹6–8 LPA · Negotiable');
    expect(salaryRangeLabel(6, 0), '₹6 LPA');
    expect(salaryRangeLabel(0, 0), '');
  });
}
