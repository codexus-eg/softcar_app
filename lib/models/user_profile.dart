/// Passenger gender — used for registration and the pink (female) / blue
/// (male) seat colour language across the booking flow.
enum UserGender {
  male,
  female;

  String get code => name.toUpperCase();

  static UserGender? fromCode(Object? value) {
    switch (value?.toString().toUpperCase()) {
      case 'MALE':
        return UserGender.male;
      case 'FEMALE':
        return UserGender.female;
      default:
        return null;
    }
  }

  String get label => name == 'female' ? 'Female' : 'Male';
}

/// The signed-in passenger's profile, taken from the backend session.
class SavedPlace {
  final String id;
  final String label;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final String placeType;
  final String? placeId;
  final bool isDefault;

  const SavedPlace({
    required this.id,
    required this.label,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    this.placeType = 'OTHER',
    this.placeId,
    this.isDefault = false,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        address: json['address']?.toString(),
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        placeType: json['placeType']?.toString() ?? 'OTHER',
        placeId: json['placeId']?.toString(),
        isDefault: json['isDefault'] as bool? ?? false,
      );

  bool get isHome => placeType == 'HOME';
  bool get isWork => placeType == 'WORK';
}

/// The signed-in passenger's profile, taken from the backend session.
class UserProfile {
  final String name;
  final String? email;
  final String? phone;
  final UserGender? gender;
  final String id;
  final String? image;
  final String preferredLanguage;
  final String preferredTheme;
  final bool pushNotifications;
  final bool emailNotifications;
  final bool phoneNotifications;
  final DateTime? dateOfBirth;
  final String? emergencyPhone;
  final String? referralCode;
  final List<SavedPlace> savedPlaces;

  const UserProfile({
    this.id = '',
    this.name = '',
    this.email,
    this.phone,
    this.gender,
    this.image,
    this.preferredLanguage = 'en',
    this.preferredTheme = 'system',
    this.pushNotifications = true,
    this.emailNotifications = true,
    this.phoneNotifications = false,
    this.dateOfBirth,
    this.emergencyPhone,
    this.referralCode,
    this.savedPlaces = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString(),
        phone: json['phone']?.toString(),
        gender: UserGender.fromCode(json['gender']),
        image: json['image']?.toString(),
        preferredLanguage: json['preferredLanguage']?.toString() ?? 'en',
        preferredTheme: json['preferredTheme']?.toString() ?? 'system',
        pushNotifications: json['pushNotifications'] as bool? ?? true,
        emailNotifications: json['emailNotifications'] as bool? ?? true,
        phoneNotifications: json['phoneNotifications'] as bool? ?? false,
        dateOfBirth: json['dateOfBirth'] != null
            ? DateTime.tryParse(json['dateOfBirth'].toString())
            : null,
        emergencyPhone: json['emergencyPhone']?.toString(),
        referralCode: json['referralCode']?.toString(),
        savedPlaces: (json['savedPlaces'] is List)
            ? (json['savedPlaces'] as List)
                  .whereType<Map>()
                  .map((p) => SavedPlace.fromJson(Map<String, dynamic>.from(p)))
                  .toList()
            : const [],
      );

  bool get hasGender => gender != null;

UserProfile copyWith({
    UserGender? gender,
    String? name,
    String? phone,
    String? email,
    String? image,
    String? preferredLanguage,
    String? preferredTheme,
    bool? pushNotifications,
    bool? emailNotifications,
    bool? phoneNotifications,
    DateTime? dateOfBirth,
    String? emergencyPhone,
    String? referralCode,
    List<SavedPlace>? savedPlaces,
  }) =>
      UserProfile(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        gender: gender ?? this.gender,
        image: image ?? this.image,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
        preferredTheme: preferredTheme ?? this.preferredTheme,
        pushNotifications: pushNotifications ?? this.pushNotifications,
        emailNotifications: emailNotifications ?? this.emailNotifications,
        phoneNotifications: phoneNotifications ?? this.phoneNotifications,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        emergencyPhone: emergencyPhone ?? this.emergencyPhone,
        referralCode: referralCode ?? this.referralCode,
        savedPlaces: savedPlaces ?? this.savedPlaces,
      );

  @override
  String toString() => 'UserProfile($name)';
}