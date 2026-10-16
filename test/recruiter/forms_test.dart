import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/recruiter/company_profile_form.dart';
import 'package:hiring_app/screens/recruiter/onboarding/company_onboarding_form.dart';

CompanyOnboardingForm validForm() => CompanyOnboardingForm(name: 'Acme Technologies', location: 'Jaipur');

void main() {
  group('company onboarding validation', () {
    test('requires name and location with the website texts', () {
      final e = CompanyOnboardingForm().validateCompany();
      expect(e['company.name'], 'Enter your company name');
      expect(e['company.location'], 'Enter your company location');
      expect(CompanyOnboardingForm(name: 'A', location: 'B').validateCompany(), isEmpty);
    });

    test('a valid form needs only the company name and location', () {
      expect(validForm().validateCompany(), isEmpty);
    });

    test('request body has only the company part (no job)', () {
      final f = validForm()
        ..industry = 'IT / Software'
        ..size = '11–50';
      final body = f.toRequestBody();
      expect(body.keys, ['company']);
      expect(body['company'], {
        'name': 'Acme Technologies',
        'industry': 'IT / Software',
        'size': '11–50',
        'location': 'Jaipur',
        'website': '',
        'about': '',
      });
    });

    test('company sizes accept the hyphen spelling', () {
      expect(canonicalCompanySize('11-50'), '11–50');
      expect(canonicalCompanySize('1000+'), '1000+');
      expect(canonicalCompanySize('lots'), '');
    });
  });

  group('company profile form', () {
    CompanyProfileForm ok() => CompanyProfileForm(name: 'Acme', location: 'Jaipur');

    test('required name and city', () {
      final e = CompanyProfileForm().validate();
      expect(e['name'], 'Enter your company name');
      expect(e['location'], 'Enter your city');
      expect(ok().validate(), isEmpty);
    });

    test('founded year, web addresses, phone, email', () {
      expect((ok()..foundedYear = '1700').validate(currentYear: 2026)['foundedYear'], 'Please enter a valid founded year');
      expect((ok()..foundedYear = '2030').validate(currentYear: 2026)['foundedYear'], 'Please enter a valid founded year');
      expect((ok()..foundedYear = '2018').validate(currentYear: 2026), isEmpty);
      expect((ok()..website = 'not a url').validate()['website'], 'Please enter a valid web address');
      expect((ok()..website = 'acme.com').validate(), isEmpty);
      expect((ok()..linkedin = 'linkedin.com/company/acme').validate(), isEmpty);
      expect((ok()..phone = '12').validate()['phone'], 'Please enter a valid phone number');
      expect((ok()..phone = '+91 98765 43210').validate(), isEmpty);
      expect((ok()..contactEmail = 'nope').validate()['contactEmail'], 'Please enter a valid email address');
      expect((ok()..contactEmail = 'careers@acme.com').validate(), isEmpty);
    });

    test('dirty tracking and body', () {
      final a = ok()..foundedYear = '2018';
      final b = a.copy();
      expect(a.sameAs(b), isTrue);
      b.about = 'We build things';
      expect(a.sameAs(b), isFalse);
      expect(a.toBody()['foundedYear'], 2018);
      expect(ok().toBody()['foundedYear'], isNull);
    });
  });
}
