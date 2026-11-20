import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/profile/domain/blocked_person.dart';
import 'package:pulse/features/profile/domain/profile_repository.dart';

/// A profile repository that answers only what a test asks it to.
///
/// Every other member is a `noSuchMethod` failure, so adding a method to
/// [ProfileRepository] never silently breaks a test with a wrong default — the
/// test that needs it fails loudly instead.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.blocked = const <BlockedPerson>[]});

  List<BlockedPerson> blocked;
  String? unblockedId;
  bool failUnblock = false;
  int blockCalls = 0;

  @override
  Future<List<BlockedPerson>> blockedPeople() async => blocked;

  @override
  Future<void> unblockUser(String targetUserId) async {
    if (failUnblock) throw const ServerFailure();
    unblockedId = targetUserId;
    blocked = [
      for (final row in blocked)
        if (row.id != targetUserId) row,
    ];
  }

  @override
  Future<void> blockUser(String targetUserId) async => blockCalls++;

  @override
  Future<bool> hasBlocked(String targetUserId) async =>
      blocked.any((row) => row.id == targetUserId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FakeProfileRepository.${invocation.memberName} was not expected here',
  );
}
