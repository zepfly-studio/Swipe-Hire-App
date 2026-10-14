/// A recruiter's company page (backend: `companies` table).
class CompanyProfile {
  final String id;
  final String name;
  final String website;
  final String about;
  final String industry;
  final String size;
  final String location;
  final String logoUrl;

  /// `unverified`, `pending` (a manual review was requested) or `verified`.
  final String verificationStatus;

  const CompanyProfile({
    required this.id,
    required this.name,
    this.website = '',
    this.about = '',
    this.industry = '',
    this.size = '',
    this.location = '',
    this.logoUrl = '',
    this.verificationStatus = 'unverified',
  });

  factory CompanyProfile.fromMap(Map<String, dynamic> map) {
    return CompanyProfile(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      website: map['website'] ?? '',
      about: map['about'] ?? '',
      industry: map['industry'] ?? '',
      size: map['size'] ?? '',
      location: map['location'] ?? '',
      logoUrl: map['logoUrl'] ?? '',
      verificationStatus: map['verificationStatus'] ?? 'unverified',
    );
  }

  bool get isVerified => verificationStatus == 'verified';
  bool get isPending => verificationStatus == 'pending';

  Map<String, dynamic> toMap() => {
        'name': name,
        'website': website,
        'about': about,
        'industry': industry,
        'size': size,
        'location': location,
        'logoUrl': logoUrl,
      };
}
