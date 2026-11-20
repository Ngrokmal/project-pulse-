/// Server-authoritative account restriction state (§25).
/// Mirrors public.account_status (migrations/0002, 0016).
enum AccountState { active, suspended, banned, underReview }

class AccountStatusInfo {
  const AccountStatusInfo({
    required this.state,
    this.reasonText,
    this.endsAt,
    this.caseCode,
    this.since,
  });

  final AccountState state;
  final String? reasonText;
  final DateTime? endsAt;

  /// The stable, human reference printed on the hold screen and on an appeal.
  /// Support reads it; nothing else depends on its shape.
  final String? caseCode;

  /// When the restriction started, as the server recorded it.
  final DateTime? since;

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
        caseCode: map['case_code'] as String?,
        since: map['starts_at'] == null
            ? null
            : DateTime.tryParse(map['starts_at'] as String)?.toLocal(),
      );

  static const activeInfo = AccountStatusInfo(state: AccountState.active);

  bool get isRestricted => state != AccountState.active;

  /// A hold with no end date. The screen says "a person is looking at this"
  /// instead of printing a date that does not exist.
  bool get isOpenEnded => isRestricted && endsAt == null;

  String get title => switch (state) {
    AccountState.active => 'Active',
    AccountState.suspended => 'Account on hold',
    AccountState.banned => 'Account access restricted',
    AccountState.underReview => 'Account under review',
  };

  /// The line under the headline. Written for a person in the middle of using
  /// the app, not for a legal department.
  String get explanation => switch (state) {
    AccountState.active => '',
    AccountState.suspended =>
      'Your email and password were right, and Pulse recognised them — then '
          'stopped before opening anything. Something this account was reported '
          'for is being looked at by a person.',
    AccountState.banned =>
      'This account can no longer use Pulse. If you believe this is a mistake, '
          'you can ask a person to look again.',
    AccountState.underReview =>
      'Our team is reviewing activity on this account. Access comes back to '
          'normal when the review closes.',
  };

  String get headlineTop => switch (state) {
    AccountState.active => '',
    AccountState.banned => 'This account is',
    _ => 'Your sign-in was right.',
  };

  String get headlineAccent => switch (state) {
    AccountState.active => '',
    AccountState.banned => 'closed.',
    _ => 'paused.',
  };

  /// What the app promises on the hold screen. Never a date it cannot keep:
  /// a window prints the window, an open-ended hold says a person is on it.
  String get commitment => endsAt != null
      ? 'Access returns after ${_formatDate(endsAt!)} unless the review says otherwise.'
      : 'A person reads every hold. You will hear back either way — no silent '
            'endings.';

  static String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
  }

  /// `ha•••••@gmail.com` — enough to recognise, not enough to leak.
  static String maskEmail(String? email) {
    if (email == null || email.isEmpty) return 'your email';
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final name = email.substring(0, at);
    final domain = email.substring(at);
    if (name.length <= 2) return '${name[0]}•••$domain';
    return '${name.substring(0, 2)}•••••$domain';
  }
}

/// One appeal, as the server stores it.
class AccountAppeal {
  const AccountAppeal({
    required this.id,
    required this.status,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? note;

  bool get isOpen => status == 'open' || status == 'reviewing';

  factory AccountAppeal.fromMap(Map<String, dynamic> map) => AccountAppeal(
    id: map['id'] as String,
    status: (map['status'] as String?) ?? 'open',
    createdAt:
        DateTime.tryParse('${map['created_at']}')?.toLocal() ?? DateTime.now(),
    note: map['note'] as String?,
  );
}

/// What the hold screen is showing at this instant.
enum HoldStage { held, received }

/// The hold as the app remembers it after the session is gone.
///
/// The session is deliberately ended when an account is suspended, so the
/// notice cannot depend on being able to read anything from the server: the
/// case, the email and the moment are captured once, at the instant of the
/// hold, and shown from memory afterwards.
class AccountHold {
  const AccountHold({required this.info, required this.since, this.email});

  final AccountStatusInfo info;
  final DateTime since;
  final String? email;

  String get maskedEmail => AccountStatusInfo.maskEmail(email);

  AccountHold copyWith({String? email}) =>
      AccountHold(info: info, since: since, email: email ?? this.email);
}

/// A submitted appeal, kept on the device so a phone that has been signed out
/// still knows what it just sent (the session is gone by design).
class AppealReceipt {
  const AppealReceipt({
    required this.reference,
    required this.submittedAt,
    required this.caseCode,
  });

  final String reference;
  final DateTime submittedAt;
  final String? caseCode;
}

abstract class AccountStatusRepository {
  Future<AccountStatusInfo> fetchMine(String userId);

  /// Fires whenever the server row changes (Realtime). A suspended phone hears
  /// about it in the same second instead of at the next launch.
  Stream<AccountStatusInfo> watch(String userId);

  /// Files an appeal for the signed-in account. Throws [AccountSuspendedFailure]
  /// only if the server refuses; a normal failure is a normal failure.
  Future<AccountAppeal> submitAppeal({
    required String userId,
    required String caseCode,
    required String note,
  });

  Future<AccountAppeal?> fetchLatestAppeal(String userId);
}
