import 'profile_privacy.dart';

/// One change that has not reached the server yet.
///
/// A settings switch has to survive a tunnel: the UI flips immediately, the
/// write is queued, and the queue drains through
/// [ProfileRepository.patchProfile] the next time the app can reach Supabase.
/// Storing the *column map* (not a card snapshot) means a queued toggle can
/// never overwrite a status line typed on another device.
class PendingWrite {
  const PendingWrite({
    required this.id,
    required this.userId,
    required this.values,
    required this.createdAt,
  });

  final String id;
  final String userId;

  /// Column → value, exactly what `update profiles set …` will receive.
  final Map<String, Object?> values;
  final DateTime createdAt;

  /// The one field this write touches, when it is a settings switch.
  PrivacyField? get privacyField {
    for (final field in PrivacyField.values) {
      if (values.containsKey(field.column)) return field;
    }
    return null;
  }

  bool get isPrivacyOnly => values.length == 1 && privacyField != null;

  int get ageSeconds => DateTime.now().difference(createdAt).inSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'user_id': userId,
    'values': values,
    'created_at': createdAt.toIso8601String(),
  };

  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
    id: (json['id'] as String?) ?? '',
    userId: (json['user_id'] as String?) ?? '',
    values: <String, Object?>{
      ...?(json['values'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      ),
    },
    createdAt:
        DateTime.tryParse((json['created_at'] as String?) ?? '') ??
        DateTime.now(),
  );
}
