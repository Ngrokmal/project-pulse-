import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/profile/domain/blocked_person.dart';
import 'package:pulse/features/profile/domain/profile.dart';
import 'package:pulse/features/profile/domain/profile_repository.dart';
import 'package:pulse/features/profile/domain/profile_visitor.dart';

/// A profile repository that answers only what a test asks it to.
///
/// Every other member is a `noSuchMethod` failure, so adding a method to
/// [ProfileRepository] never silently breaks a test with a wrong default — the
/// test that needs it fails loudly instead.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.blocked = const <BlockedPerson>[],
    this.visitors = const <ProfileVisitor>[],
    this.peer,
    this.failVisitors = false,
    this.failVisit = false,
  });

  List<BlockedPerson> blocked;
  List<ProfileVisitor> visitors;

  /// The card `/u/:id` should open.
  Profile? peer;

  bool failVisitors;
  bool failVisit;

  /// Every visit this fake was asked to record, in order.
  final List<String> recordedVisits = <String>[];

  @override
  Future<List<ProfileVisitor>> profileVisitors({int limit = 50}) async {
    if (failVisitors) throw const ServerFailure();
    return visitors;
  }

  @override
  Future<void> recordProfileVisit(String targetUserId) async {
    if (failVisit) throw const ServerFailure();
    recordedVisits.add(targetUserId);
  }

  @override
  Future<Profile> fetchProfile(String userId) async {
    final card = peer;
    if (card == null) throw const ServerFailure(safeCode: 'profile_missing');
    return card;
  }

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
