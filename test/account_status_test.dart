import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/account_status/domain/account_status.dart';

void main() {
  test('maps every database enum value', () {
    expect(
      AccountStatusInfo.fromMap({'status': 'active'}).state,
      AccountState.active,
    );
    expect(
      AccountStatusInfo.fromMap({'status': 'suspended'}).state,
      AccountState.suspended,
    );
    expect(
      AccountStatusInfo.fromMap({'status': 'banned'}).state,
      AccountState.banned,
    );
    expect(
      AccountStatusInfo.fromMap({'status': 'under_review'}).state,
      AccountState.underReview,
    );
  });

  test('unknown value never fabricates a restriction', () {
    expect(AccountStatusInfo.fromMap({'status': null}).isRestricted, isFalse);
    expect(
      AccountStatusInfo.fromMap({'status': 'weird_future_value'}).isRestricted,
      isFalse,
    );
  });

  test('restricted states expose title + explanation for the UI (§25)', () {
    for (final state in [
      AccountState.suspended,
      AccountState.banned,
      AccountState.underReview,
    ]) {
      final info = AccountStatusInfo(state: state);
      expect(info.isRestricted, isTrue);
      expect(info.title.trim(), isNotEmpty);
      expect(info.explanation.trim(), isNotEmpty);
    }
  });

  test('active state is not treated as restricted', () {
    expect(AccountStatusInfo.activeInfo.isRestricted, isFalse);
  });
}
