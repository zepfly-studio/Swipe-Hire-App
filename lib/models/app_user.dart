/// The two account types SwipeHire supports. A [recruiter] is the company
/// or person doing the hiring (today's swipe/shortlist experience); a
/// [candidate] is the job seeker being discovered.
enum UserRole { recruiter, candidate }

extension UserRoleX on UserRole {
  String get value => this == UserRole.recruiter ? 'recruiter' : 'candidate';

  static UserRole fromString(String value) {
    return value == 'recruiter' ? UserRole.recruiter : UserRole.candidate;
  }
}

/// The `users/{uid}` Firestore profile backing a signed-in Firebase Auth
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

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.company = '',
    this.designation = '',
    this.phone = '',
    this.profileComplete = false,
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
    };
  }
}
