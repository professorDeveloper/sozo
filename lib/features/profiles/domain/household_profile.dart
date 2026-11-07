/// One person in a household account, as `GET /auth/profiles` returns it.
class HouseholdProfile {
  const HouseholdProfile({
    required this.id,
    required this.name,
    this.avatar,
    this.color,
    this.isKids = false,
    this.isDefault = false,
    this.hasPin = false,
  });

  final String id;
  final String name;

  /// A preset id (see `ProfileAvatars`), never a URL.
  final String? avatar;

  /// `#rrggbb`.
  final String? color;
  final bool isKids;
  final bool isDefault;
  final bool hasPin;

  /// Where this profile's data lives on the device; null for the default
  /// profile, which keeps the boxes the app has always used.
  String? get namespace => isDefault ? null : id;

  factory HouseholdProfile.fromJson(Map<String, dynamic> json) =>
      HouseholdProfile(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        avatar: json['avatar'] as String?,
        color: json['color'] as String?,
        isKids: json['isKids'] == true,
        isDefault: json['isDefault'] == true,
        hasPin: json['hasPin'] == true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'color': color,
    'isKids': isKids,
    'isDefault': isDefault,
    'hasPin': hasPin,
  };

  @override
  bool operator ==(Object other) =>
      other is HouseholdProfile &&
      other.id == id &&
      other.name == name &&
      other.avatar == avatar &&
      other.color == color &&
      other.isKids == isKids &&
      other.isDefault == isDefault &&
      other.hasPin == hasPin;

  @override
  int get hashCode =>
      Object.hash(id, name, avatar, color, isKids, isDefault, hasPin);
}

/// What the profiles endpoints refuse with. [code] is the server's machine
/// code (`PIN_INVALID`, `PROFILE_LIMIT`, ...), or one the device checked the
/// PIN with (`PIN_LOCKED`, `PIN_NOT_ON_DEVICE`); null for network failures.
class ProfileException implements Exception {
  const ProfileException(
    this.message, {
    this.code,
    this.status,
    this.retryAt,
  });

  final String message;
  final String? code;
  final int? status;

  /// When the next guess is allowed, after too many wrong ones on the device.
  final DateTime? retryAt;

  bool get isOffline => status == null && code == null;

  /// The server could not be asked at all, or its gateway said so. A refusal
  /// (a wrong PIN, a rate limit) is an answer and never counts.
  bool get isUnreachable =>
      isOffline || status == 502 || status == 503 || status == 504;

  @override
  String toString() => message;
}
