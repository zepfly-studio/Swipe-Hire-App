/// The signed-in recruiter's own company (GET /company/me), including the
/// private contact fields and the swipe balance.
class HiringCompany {
  final String id;
  final String name;
  final String website;
  final String about;
  final String industry;
  final String size;
  final String location;
  final String logoUrl;
  final String address;
  final String phone;
  final String contactEmail;
  final String linkedin;
  final int? foundedYear;

  /// unverified | pending | verified | rejected
  final String verificationStatus;
  final bool verified;
  final int swipesLeft;
  final int swipesPurchased;

  const HiringCompany({
    this.id = '',
    this.name = '',
    this.website = '',
    this.about = '',
    this.industry = '',
    this.size = '',
    this.location = '',
    this.logoUrl = '',
    this.address = '',
    this.phone = '',
    this.contactEmail = '',
    this.linkedin = '',
    this.foundedYear,
    this.verificationStatus = 'unverified',
    this.verified = false,
    this.swipesLeft = 0,
    this.swipesPurchased = 0,
  });

  bool get isPending => verificationStatus == 'pending';

  factory HiringCompany.fromMap(Map<String, dynamic> m) {
    String s(String k) => (m[k] ?? '').toString();
    final status = m['verificationStatus'] == null ? 'unverified' : s('verificationStatus');
    return HiringCompany(
      id: s('id'),
      name: s('name'),
      website: s('website'),
      about: s('about'),
      industry: s('industry'),
      size: s('size'),
      location: s('location'),
      logoUrl: s('logoUrl'),
      address: s('address'),
      phone: s('phone'),
      contactEmail: s('contactEmail'),
      linkedin: s('linkedin'),
      foundedYear: (m['foundedYear'] as num?)?.toInt(),
      verificationStatus: status,
      verified: m['verified'] == true || status == 'verified',
      swipesLeft: (m['swipesLeft'] as num?)?.toInt() ?? 0,
      swipesPurchased: (m['swipesPurchased'] as num?)?.toInt() ?? 0,
    );
  }
}
