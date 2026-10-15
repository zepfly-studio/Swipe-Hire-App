import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/hiring_job.dart';
import 'package:hiring_app/screens/recruiter/company_profile_form.dart';
import 'package:hiring_app/screens/recruiter/jobs/job_form.dart';
import 'package:hiring_app/screens/recruiter/onboarding/company_onboarding_form.dart';

CompanyOnboardingForm validForm() => CompanyOnboardingForm(
      name: 'Acme Technologies',
      location: 'Jaipur',
      role: 'Frontend Developer',
      skills: ['React'],
      maxSalary: '8',
    );

void main() {
  group('company onboarding validation', () {
    test('step 1 requires name and location with the website texts', () {
      final e = CompanyOnboardingForm().validateCompany();
      expect(e['company.name'], 'Enter your company name');
      expect(e['company.location'], 'Enter your company location');
      expect(CompanyOnboardingForm(name: 'A', location: 'B').validateCompany(), isEmpty);
    });

    test('step 2 requires role, a skill and the max salary', () {
      final e = CompanyOnboardingForm().validateJob();
      expect(e['job.title'], 'Enter the role you are hiring for');
      expect(e['job.skills'], 'Add at least one skill');
      expect(e['job.salaryMaxLpa'], 'Enter the maximum salary you can offer');
      expect(validForm().validateAll(), isEmpty);
    });

    test('experience range and ordering', () {
      final f = validForm()
        ..minExp = '60'
        ..maxExp = '-1';
      final e = f.validateJob();
      expect(e['job.minExperienceYears'], 'Enter years between 0 and 50');
      expect(e['job.maxExperienceYears'], 'Enter years between 0 and 50');

      final g = validForm()
        ..minExp = '6'
        ..maxExp = '3';
      expect(g.validateJob()['job.minExperienceYears'], 'Must be less than maximum');
    });

    test('salary: invalid, over 1000 LPA, min above max, rupee amounts convert', () {
      expect((validForm()..maxSalary = 'abc').validateJob()['job.salaryMaxLpa'], 'Enter a valid salary');
      expect((validForm()..maxSalary = '2000000000').validateJob()['job.salaryMaxLpa'], 'Enter a valid salary');
      expect(
        (validForm()
              ..minSalary = '9'
              ..maxSalary = '8')
            .validateJob()['job.salaryMinLpa'],
        'Must be less than maximum',
      );
      final f = validForm()..maxSalary = '800000';
      expect(f.validateJob(), isEmpty);
      expect(f.jobBody()['salaryMaxLpa'], 8);
    });

    test('request body has company and job parts; job location defaults to the company', () {
      final f = validForm()
        ..industry = 'IT / Software'
        ..size = '11–50'
        ..minExp = '1'
        ..maxExp = '4'
        ..minSalary = '3'
        ..workMode = 'hybrid';
      final body = f.toRequestBody();
      expect(body['company'], {
        'name': 'Acme Technologies',
        'industry': 'IT / Software',
        'size': '11–50',
        'location': 'Jaipur',
        'website': '',
        'about': '',
      });
      final job = body['job'] as Map<String, dynamic>;
      expect(job['title'], 'Frontend Developer');
      expect(job['skills'], ['React']);
      expect(job['minExperienceYears'], 1);
      expect(job['maxExperienceYears'], 4);
      expect(job['salaryMinLpa'], 3);
      expect(job['salaryMaxLpa'], 8);
      expect(job['location'], 'Jaipur');
      expect(job['workMode'], 'hybrid');
    });

    test('server fields jump to the right step', () {
      expect(onboardingStepForField('company.name'), 0);
      expect(onboardingStepForField('company.location'), 0);
      expect(onboardingStepForField('website'), 0);
      expect(onboardingStepForField('job.title'), 1);
      expect(onboardingStepForField('job.salaryMaxLpa'), 1);
      expect(onboardingStepForField('skills'), 1);
    });

    test('company sizes accept the hyphen spelling', () {
      expect(canonicalCompanySize('11-50'), '11–50');
      expect(canonicalCompanySize('1000+'), '1000+');
      expect(canonicalCompanySize('lots'), '');
    });
  });

  group('job form', () {
    test('required fields and messages', () {
      final e = JobForm().validate();
      expect(e['title'], 'Enter the role you are hiring for');
      expect(e['skills'], 'Add at least one skill');
      expect(e['salaryMaxLpa'], 'Enter the maximum salary');
    });

    test('min above max messages', () {
      final f = JobForm(title: 'Dev', skills: ['Go'], maxSalary: '8', minSalary: '9', minExp: '5', maxExp: '2');
      final e = f.validate();
      expect(e['minExperienceYears'], 'Minimum experience cannot be more than maximum experience');
      expect(e['salaryMinLpa'], 'Minimum salary cannot be more than maximum salary');
    });

    test('openings between 1 and 1000', () {
      final base = JobForm(title: 'Dev', skills: ['Go'], maxSalary: '8');
      expect((base..openings = '0').validate().containsKey('openings'), isTrue);
      expect((base..openings = '1001').validate().containsKey('openings'), isTrue);
      expect((base..openings = '3').validate(), isEmpty);
    });

    test('body, and editing round-trips a job', () {
      const job = HiringJob(
        id: 'j1',
        title: 'Designer',
        skills: ['Figma'],
        location: 'Pune',
        workMode: 'remote',
        employmentType: 'contract',
        openings: 2,
        salaryMinLpa: 4,
        salaryMaxLpa: 9.5,
        minExperienceYears: 1,
        maxExperienceYears: null,
      );
      final form = JobForm.fromJob(job);
      expect(form.validate(), isEmpty);
      final body = form.toBody();
      expect(body['title'], 'Designer');
      expect(body['workMode'], 'remote');
      expect(body['employmentType'], 'contract');
      expect(body['openings'], 2);
      expect(body['salaryMaxLpa'], 9.5);
      expect(body['maxExperienceYears'], isNull);
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
