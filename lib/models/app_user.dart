/// The two account types GlideRecruit supports. A [recruiter] is the company
/// or person doing the hiring (today's swipe/shortlist experience); a
/// [candidate] is the job seeker being discovered.
enum UserRole { recruiter, candidate }

extension UserRoleX on UserRole {
  String get value => this == UserRole.recruiter ? 'recruiter' : 'candidate';

  static UserRole fromString(String value) {
    return value == 'recruiter' ? UserRole.recruiter : UserRole.candidate;
  }
}

/// The backend `users` row (Postgres) backing a signed-in Firebase Auth
/// account -- holds the role that decides which home screen [AuthGate]
/// routes to, and [profileComplete], which decides whether it routes
/// through [CompleteProfileScreen] first.
class AppUser {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final String company;
  final String designation;
  final String phone;
  final bool profileComplete;

  /// Whether important updates are also emailed.
  final bool emailNotifications;

  /// GlideRecruit staff (the email is in the server's ADMIN_EMAILS list).
  final bool isAdmin;

  /// A recruiter who owns the company. False for a team member who joined
  /// through an invite (they cannot invite people or rename the company).
  final bool isOwner;

  /// The hiring account the recruiter works under: the owner's user id.
  final String companyId;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.company = '',
    this.designation = '',
    this.phone = '',
    this.profileComplete = false,
    this.emailNotifications = true,
    this.isAdmin = false,
    this.isOwner = true,
    this.companyId = '',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: UserRoleX.fromString(map['role'] ?? 'candidate'),
      company: map['company'] ?? '',
      designation: map['designation'] ?? '',
      phone: map['phone'] ?? '',
      profileComplete: map['profileComplete'] ?? false,
      emailNotifications: map['emailNotifications'] ?? true,
      isAdmin: map['isAdmin'] == true,
      isOwner: map['isOwner'] != false,
      companyId: (map['companyId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role.value,
      'company': company,
      'designation': designation,
      'phone': phone,
      'profileComplete': profileComplete,
      'emailNotifications': emailNotifications,
      'isAdmin': isAdmin,
      'isOwner': isOwner,
      'companyId': companyId,
    };
  }
}
