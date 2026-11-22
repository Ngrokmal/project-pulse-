import 'package:hive_ce/hive.dart';

/// Non-destructive primitive for a future encrypted-box migration. The caller
/// must stop ALL writers to both boxes for the entire operation and supply an
/// already-opened encrypted destination with a securely managed key. It does
/// not infer ownership, delete the source, activate the destination, or itself
/// establish that the destination is encrypted. Not wired into production.
Future<int> copyHiveStringsWithoutDeleting({
  required Box<String> source,
  required Box<String> destination,
}) async {
  if (identical(source, destination)) throw ArgumentError('boxes must differ');
  final entries = <dynamic, String>{};
  for (final key in source.keys) {
    final value = source.get(key);
    if (value == null) throw StateError('source changed during copy');
    entries[key] = value;
  }
  // Refuse to overwrite a destination conflict. This permits crash/retry of a
  // partial copy but never silently replaces a distinct recovered draft.
  for (final entry in entries.entries) {
    final existing = destination.get(entry.key);
    if (existing != null && existing != entry.value) {
      throw StateError('destination conflict');
    }
  }
  var copied = 0;
  for (final entry in entries.entries) {
    if (!destination.containsKey(entry.key)) {
      await destination.put(entry.key, entry.value);
      copied++;
    }
  }
  await destination.flush();
  for (final entry in entries.entries) {
    if (destination.get(entry.key) != entry.value ||
        source.get(entry.key) != entry.value) {
      throw StateError('copy verification failed');
    }
  }
  if (source.length != entries.length) {
    throw StateError('source changed during copy');
  }
  return copied;
}
