/// Raw values of the company profile form (spec C7) with validation and the
/// PUT /company/me body.
class CompanyProfileForm {
  String name;
  String industry;
  String size;
  String foundedYear;
  String about;
  String website;
  String linkedin;
  String phone;
  String contactEmail;
  String location;
  String address;

  CompanyProfileForm({
    this.name = '',
    this.industry = '',
    this.size = '',
    this.foundedYear = '',
    this.about = '',
    this.website = '',
    this.linkedin = '',
    this.phone = '',
    this.contactEmail = '',
    this.location = '',
    this.address = '',
  });

  CompanyProfileForm copy() => CompanyProfileForm(
        name: name,
        industry: industry,
        size: size,
        foundedYear: foundedYear,
        about: about,
        website: website,
        linkedin: linkedin,
        phone: phone,
        contactEmail: contactEmail,
        location: location,
        address: address,
      );

  Map<String, String> toMap() => {
        'name': name.trim(),
        'industry': industry,
        'size': size,
        'foundedYear': foundedYear.trim(),
        'about': about.trim(),
        'website': website.trim(),
        'linkedin': linkedin.trim(),
        'phone': phone.trim(),
        'contactEmail': contactEmail.trim(),
        'location': location.trim(),
        'address': address.trim(),
      };

  bool sameAs(CompanyProfileForm other) {
    final a = toMap();
    final b = other.toMap();
    return a.entries.every((e) => b[e.key] == e.value);
  }

  static final RegExp _phoneRe = RegExp(r'^\+?[\d\s-]{8,16}$');
  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool _looksLikeUrl(String v) {
    final t = v.trim();
    if (t.isEmpty) return true;
    if (t.contains(RegExp(r'\s'))) return false;
    final host = t.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').split('/').first;
    return host.contains('.') && !host.startsWith('.') && !host.endsWith('.');
  }

  /// Field -> message (keys match the server's `field` values).
  Map<String, String> validate({int? currentYear}) {
    final e = <String, String>{};
    final n = name.trim();
    if (n.length < 2) {
      e['name'] = 'Enter your company name';
    } else if (n.length > 100) {
      e['name'] = 'Company name can be up to 100 characters';
    }
    if (location.trim().isEmpty) e['location'] = 'Enter your city';
    if (foundedYear.trim().isNotEmpty) {
      final y = int.tryParse(foundedYear.trim());
      final max = currentYear ?? DateTime.now().year;
      if (y == null || y < 1800 || y > max) e['foundedYear'] = 'Please enter a valid founded year';
    }
    if (!_looksLikeUrl(website)) e['website'] = 'Please enter a valid web address';
    if (!_looksLikeUrl(linkedin)) e['linkedin'] = 'Please enter a valid web address';
    if (phone.trim().isNotEmpty && !_phoneRe.hasMatch(phone.trim())) {
      e['phone'] = 'Please enter a valid phone number';
    }
    if (contactEmail.trim().isNotEmpty && !_emailRe.hasMatch(contactEmail.trim())) {
      e['contactEmail'] = 'Please enter a valid email address';
    }
    return e;
  }

  /// The PUT /company/me body (`foundedYear` as a number or null).
  Map<String, dynamic> toBody() {
    final m = toMap();
    return {
      ...m,
      'foundedYear': int.tryParse(m['foundedYear']!),
    };
  }
}
