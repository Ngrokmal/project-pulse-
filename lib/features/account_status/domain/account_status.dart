/// Server-authoritative account restriction state (§25).
/// Mirrors public.account_status (migrations/0002).
enum AccountState { active, suspended, banned, underReview }

class AccountStatusInfo {
  const AccountStatusInfo({required this.state, this.reasonText, this.endsAt});

  final AccountState state;
  final String? reasonText;
  final DateTime? endsAt;

  static AccountState _parse(String? raw) => switch (raw) {
    'active' => AccountState.active,
    'suspended' => AccountState.suspended,
    'banned' => AccountState.banned,
    'under_review' => AccountState.underReview,
    _ => AccountState.active,
  };

  factory AccountStatusInfo.fromMap(Map<String, dynamic> map) =>
      AccountStatusInfo(
        state: _parse(map['status'] as String?),
        reasonText: map['reason_text'] as String?,
        endsAt: map['ends_at'] == null
            ? null
            : DateTime.tryParse(map['ends_at'] as String)?.toLocal(),
      );

  static const activeInfo = AccountStatusInfo(state: AccountState.active);

  bool get isRestricted => state != AccountState.active;

  String get title => switch (state) {
    AccountState.active => 'Active',
    AccountState.suspended => 'Account temporarily suspended',
    AccountState.banned => 'Account access restricted',
    AccountState.underReview => 'Account under review',
  };

  String get explanation => switch (state) {
    AccountState.active => '',
    AccountState.suspended => 'Your account has limited access for now. You will be able to use Pulse again once the period ends.',
    AccountState.banned => 'This account can no longer use Pulse. If you believe this is a mistake, please refer to our policies.',
    AccountState.underReview => 'Our team is reviewing activity on this account. Access will return to normal after the review.',
  };
}

abstract class AccountStatusRepository {
  Future<AccountStatusInfo> fetchMine(String userId);
}
