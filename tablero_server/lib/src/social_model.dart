import 'glicko.dart';

/// Amistad entre dos cuentas (`friendships/{a_b}`, uids ordenados).
class Friendship {
  final List<String> users; // ordenados
  final String status; // pending | accepted | blocked
  final String requestedBy;
  final String? blockedBy;
  final Map<String, String> names; // uid → nombre de usuario
  final DateTime createdAt;
  final DateTime updatedAt;

  const Friendship({
    required this.users,
    required this.status,
    required this.requestedBy,
    this.blockedBy,
    required this.names,
    required this.createdAt,
    required this.updatedAt,
  });

  static String keyFor(String a, String b) => (a.compareTo(b) < 0 ? [a, b] : [b, a]).join('_');
  static List<String> sorted(String a, String b) => a.compareTo(b) < 0 ? [a, b] : [b, a];

  String get key => users.join('_');
  String other(String uid) => users[0] == uid ? users[1] : users[0];

  Friendship copyWith({String? status, String? blockedBy, Map<String, String>? names, required DateTime updatedAt}) =>
      Friendship(
        users: users,
        status: status ?? this.status,
        requestedBy: requestedBy,
        blockedBy: blockedBy ?? this.blockedBy,
        names: names ?? this.names,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toFields() => {
        'users': users,
        'status': status,
        'requestedBy': requestedBy,
        'blockedBy': blockedBy,
        'names': names,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Friendship.fromFields(Map<String, Object?> f) => Friendship(
        users: [for (final u in f['users'] as List) u as String],
        status: f['status'] as String,
        requestedBy: f['requestedBy'] as String,
        blockedBy: f['blockedBy'] as String?,
        names: {for (final e in (f['names'] as Map? ?? const {}).entries) e.key as String: e.value as String},
        createdAt: f['createdAt'] as DateTime,
        updatedAt: f['updatedAt'] as DateTime,
      );
}

/// Valoraciones de una cuenta (`ratings/{uid}`): una por juego, y las partidas
/// valoradas recientes contra cada rival (para el límite anti-abuso).
class RatingsDoc {
  final Map<String, Rating> ratings;
  final Map<String, List<DateTime>> recent;
  const RatingsDoc({this.ratings = const {}, this.recent = const {}});

  Rating of(String key) => ratings[key] ?? const Rating();

  Map<String, Object?> toFields() => {
        'ratings': {for (final e in ratings.entries) e.key: e.value.toFields()},
        'recent': {for (final e in recent.entries) e.key: e.value},
      };

  factory RatingsDoc.fromFields(Map<String, Object?> f) => RatingsDoc(
        ratings: {
          for (final e in (f['ratings'] as Map? ?? const {}).entries)
            e.key as String: Rating.fromFields(Map<String, Object?>.from(e.value as Map)),
        },
        recent: {
          for (final e in (f['recent'] as Map? ?? const {}).entries)
            e.key as String: [for (final t in e.value as List) t as DateTime],
        },
      );
}

/// Entrada de una clasificación.
typedef LeaderboardEntry = ({String uid, String username, int rating, int games});
