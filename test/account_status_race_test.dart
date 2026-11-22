import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/account_status/application/account_status_controller.dart';
import 'package:pulse/features/account_status/domain/account_status.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(PulseUser(id: 'a', email: null));
  void switchTo(String id) =>
      state = AuthSignedIn(PulseUser(id: id, email: null));
}

class _Lock extends AccountLockController {
  @override
  Future<void> endSession() async {}
}

class _Repo implements AccountStatusRepository {
  final requests = <String, List<Completer<AccountStatusInfo>>>{};
  final streams = <String, StreamController<AccountStatusInfo>>{};
  @override
  Future<AccountStatusInfo> fetchMine(String userId) {
    final result = Completer<AccountStatusInfo>();
    requests.putIfAbsent(userId, () => []).add(result);
    return result.future;
  }

  @override
  Stream<AccountStatusInfo> watch(String userId) => streams
      .putIfAbsent(
        userId,
        () => StreamController<AccountStatusInfo>.broadcast(),
      )
      .stream;
  @override
  Future<AccountAppeal?> fetchLatestAppeal(String userId) async => null;
  @override
  Future<AccountAppeal> submitAppeal({
    required String userId,
    required String caseCode,
    required String note,
  }) => throw UnimplementedError();
}

void main() {
  test('old account status response cannot lock a switched account', () async {
    final repo = _Repo();
    final c = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        accountStatusRepositoryProvider.overrideWithValue(repo),
        accountLockProvider.overrideWith(_Lock.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      for (final stream in repo.streams.values) {
        await stream.close();
      }
    });
    final subscription = c.listen(
      accountStatusControllerProvider,
      (a, b) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await c.pump();
    expect(repo.requests['a'], hasLength(1));
    (c.read(authControllerProvider.notifier) as _Auth).switchTo('b');
    await c.pump();
    expect(repo.requests['b'], hasLength(1));
    repo.requests['b']!.single.complete(AccountStatusInfo.activeInfo);
    await c.pump();
    repo.requests['a']!.single.complete(
      const AccountStatusInfo(state: AccountState.suspended),
    );
    await c.pump();
    expect(c.read(accountLockProvider), isNull);
    expect(
      c.read(accountStatusControllerProvider).value?.state,
      AccountState.active,
    );
    expect(repo.streams.containsKey('a'), isFalse);
  });

  test('a pending status check cannot lock the next account', () async {
    final repo = _Repo();
    final c = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        accountStatusRepositoryProvider.overrideWithValue(repo),
        accountLockProvider.overrideWith(_Lock.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      for (final stream in repo.streams.values) {
        await stream.close();
      }
    });
    final sub = c.listen(
      accountStatusControllerProvider,
      (a, b) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await c.pump();
    repo.requests['a']!.first.complete(AccountStatusInfo.activeInfo);
    await c.pump();
    final oldCheck = c.read(accountStatusControllerProvider.notifier).check();
    (c.read(authControllerProvider.notifier) as _Auth).switchTo('b');
    await c.pump();
    repo.requests['b']!.first.complete(AccountStatusInfo.activeInfo);
    await c.pump();
    repo.requests['a']!.last.complete(
      const AccountStatusInfo(state: AccountState.suspended),
    );
    await oldCheck;
    await c.pump();
    expect(c.read(accountLockProvider), isNull);
    expect(
      c.read(accountStatusControllerProvider).value?.state,
      AccountState.active,
    );
  });
}
