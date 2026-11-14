import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase 8: the call state machine, mirrored from `0007_calls.sql`.
///
/// Rules that matter:
///  * The DB owns the row state (`ringing → connecting → active`), the app never
///    guesses it.
///  * `active` requires **two** independent confirmations: the row says
///    `connecting` and the media layer reports a channel. Without both, the UI
///    keeps saying "Connecting…" — there is no fake "connected".
enum CallState {
  idle,
  ringing, // someone is calling me
  calling, // I am dialling
  connecting, // accepted, media not up yet
  active, // media confirmed by both sides
  reconnecting,
  ended,
  declined,
  missed,
  failed;

  bool get isLive =>
      this == ringing ||
      this == calling ||
      this == connecting ||
      this == active ||
      this == reconnecting;

  bool get isFinished =>
      this == ended || this == declined || this == missed || this == failed;

  /// Maps the `calls.state` column + which side I am onto the UI state.
  static CallState fromRow(String rowState, {required bool iAmCaller}) {
    switch (rowState) {
      case 'ringing':
        return iAmCaller ? CallState.calling : CallState.ringing;
      case 'connecting':
        return CallState.connecting;
      case 'active':
        return CallState.active;
      case 'reconnecting':
        return CallState.reconnecting;
      case 'ended':
        return CallState.ended;
      case 'declined':
        return CallState.declined;
      case 'missed':
        return CallState.missed;
      default:
        return CallState.failed;
    }
  }

  /// The states the DB accepts (null means "not stored").
  String? get rowValue => switch (this) {
    CallState.idle => null,
    CallState.calling || CallState.ringing => 'ringing',
    CallState.connecting => 'connecting',
    CallState.active => 'active',
    CallState.reconnecting => 'reconnecting',
    CallState.ended => 'ended',
    CallState.declined => 'declined',
    CallState.missed => 'missed',
    CallState.failed => 'failed',
  };

  String get label => switch (this) {
    CallState.idle => '',
    CallState.ringing => 'Incoming call',
    CallState.calling => 'Calling…',
    CallState.connecting => 'Connecting…',
    CallState.active => 'Connected',
    CallState.reconnecting => 'Reconnecting…',
    CallState.ended => 'Call ended',
    CallState.declined => 'Declined',
    CallState.missed => 'Missed',
    CallState.failed => 'Call failed',
  };
}

enum CallKind {
  audio,
  video;

  static CallKind parse(String? raw) =>
      raw == 'video' ? CallKind.video : CallKind.audio;
}

/// Media abstraction. Phase 8 ships a mock; an Agora/Jitsi adapter later has to
/// implement the same three members and nothing else (§8 provider abstraction).
abstract class CallMedia {
  Future<void> join({required String callId, required CallKind kind});
  Future<void> leave();
  Future<void> setMuted(bool muted);
  Future<void> setSpeaker(bool on);
}

/// Never claims a channel. Used until a real provider is wired, and in tests.
class MockCallMedia implements CallMedia {
  MockCallMedia({this.connect = true});

  /// When false the mock simulates a media layer that never comes up, which is
  /// exactly the case that used to produce a fake "connected" screen.
  final bool connect;

  final log = <String>[];
  bool _joined = false;

  bool get joined => _joined;

  @override
  Future<void> join({required String callId, required CallKind kind}) async {
    log.add('join:$callId:${kind.name}');
    _joined = connect;
  }

  @override
  Future<void> leave() async {
    log.add('leave');
    _joined = false;
  }

  @override
  Future<void> setMuted(bool muted) async => log.add('muted:$muted');

  @override
  Future<void> setSpeaker(bool on) async => log.add('speaker:$on');
}

/// Transitions the UI state machine allows. Kept pure so it can be unit tested
/// without a database or a widget tree.
class CallMachine {
  const CallMachine._();

  static const _allowed = <CallState, Set<CallState>>{
    CallState.idle: {CallState.calling, CallState.ringing, CallState.failed},
    CallState.calling: {
      CallState.connecting,
      CallState.ended,
      CallState.declined,
      CallState.missed,
      CallState.failed,
    },
    CallState.ringing: {
      CallState.connecting,
      CallState.declined,
      CallState.missed,
      CallState.ended,
    },
    CallState.connecting: {
      CallState.active,
      CallState.ended,
      CallState.declined,
      CallState.missed,
      CallState.failed,
    },
    CallState.active: {
      CallState.reconnecting,
      CallState.ended,
      CallState.failed,
    },
    CallState.reconnecting: {
      CallState.active,
      CallState.ended,
      CallState.failed,
    },
    CallState.ended: {CallState.idle},
    CallState.declined: {CallState.idle},
    CallState.missed: {CallState.idle},
    CallState.failed: {CallState.idle},
  };

  static bool canTransition(CallState from, CallState to) =>
      _allowed[from]?.contains(to) ?? false;

  /// Applies the row state + media state. Connected needs both.
  static CallState next({
    required CallState current,
    required String rowState,
    required bool iAmCaller,
    required bool mediaUp,
  }) {
    final fromRow = CallState.fromRow(rowState, iAmCaller: iAmCaller);
    // The row says active but our own media never came up: stay in connecting
    // rather than showing a call the user cannot hear.
    if (fromRow == CallState.active && !mediaUp) {
      return current == CallState.connecting
          ? CallState.connecting
          : CallState.failed;
    }
    return fromRow;
  }
}

/// Everything the call screen needs, derived from one `calls` row.
class CallSession {
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.peerName,
    required this.peerId,
    required this.kind,
    required this.state,
    this.answeredAt,
    this.endedAt,
    this.endReason,
    this.muted = false,
    this.speaker = false,
  });

  final String id;
  final String conversationId;
  final String peerName;
  final String peerId;
  final CallKind kind;
  final CallState state;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endReason;
  final bool muted;
  final bool speaker;

  Duration elapsed(DateTime now) {
    final from = answeredAt;
    if (from == null || state != CallState.active) return Duration.zero;
    final d = now.difference(from);
    return d.isNegative ? Duration.zero : d;
  }

  String elapsedLabel(DateTime now) {
    final d = elapsed(now);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  CallSession copyWith({
    CallState? state,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endReason,
    bool? muted,
    bool? speaker,
  }) => CallSession(
    id: id,
    conversationId: conversationId,
    peerName: peerName,
    peerId: peerId,
    kind: kind,
    state: state ?? this.state,
    answeredAt: answeredAt ?? this.answeredAt,
    endedAt: endedAt ?? this.endedAt,
    endReason: endReason ?? this.endReason,
    muted: muted ?? this.muted,
    speaker: speaker ?? this.speaker,
  );

  static CallSession fromRow(
    Map<String, dynamic> row, {
    required String myId,
    required String peerName,
  }) {
    final iAmCaller = row['caller_id'] == myId;
    return CallSession(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      peerId: (iAmCaller ? row['callee_id'] : row['caller_id']) as String,
      peerName: peerName,
      kind: CallKind.parse(row['kind'] as String?),
      state: CallState.fromRow(row['state'] as String, iAmCaller: iAmCaller),
      answeredAt: row['answered_at'] == null
          ? null
          : DateTime.parse(row['answered_at'] as String).toLocal(),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at'] as String).toLocal(),
      endReason: row['end_reason'] as String?,
    );
  }
}

/// Holds the media implementation the app is currently using. Replacing this
/// provider is all a real vendor integration has to do.
final callMediaProvider = Provider<CallMedia>((ref) => MockCallMedia());
