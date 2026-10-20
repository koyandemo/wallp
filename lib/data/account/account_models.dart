/// The JSON shapes of the optional account API (docs/app-api.md §3).
library;

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  /// What the Me tab calls the user.
  String get name => displayName.isEmpty ? email : displayName;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// Register, login and refresh all answer with this.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
  );

  final String accessToken;
  final String refreshToken;

  /// When [accessToken] stops working. Read it; never assume 15 minutes.
  final DateTime expiresAt;
  final AppUser user;
}

/// One signed-in login, for "Where you're signed in".
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.userAgent,
    required this.ip,
    required this.createdAt,
    required this.expiresAt,
    required this.current,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
    id: json['id'] as String,
    userAgent: json['userAgent'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    current: json['current'] as bool? ?? false,
  );

  /// The login (token family) ID.
  final String id;
  final String userAgent;
  final String ip;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// This phone.
  final bool current;
}

/// Item types the server keeps favourites for.
abstract final class FavouriteType {
  static const theme = 'theme';
  static const wallpaper = 'wallpaper';
  static const font = 'font';
  static const iconPack = 'icon-pack';
}

class FavouriteItem {
  const FavouriteItem(this.itemType, this.itemId, [this.createdAt]);

  factory FavouriteItem.fromJson(Map<String, dynamic> json) => FavouriteItem(
    json['itemType'] as String,
    json['itemId'] as String,
    DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  final String itemType;
  final String itemId;
  final DateTime? createdAt;

  String get key => '$itemType/$itemId';

  Map<String, Object?> toJson() => {'itemType': itemType, 'itemId': itemId};
}
