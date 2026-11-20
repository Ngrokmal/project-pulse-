import 'profile.dart';
import 'profile_time.dart';
import 'profile_view_mode.dart';

/// The four things the "Right now" grid may show — and, for each one, the
/// sentence that says where the value came from.
///
/// The rule the whole grid exists to encode: **nothing is inferred**. A value
/// appears because its owner stored it, and it disappears the moment they
/// clear it.
enum RightNowKind { status, localTime, where, joined }

class RightNowEntry {
  const RightNowEntry({
    required this.kind,
    required this.label,
    required this.value,
    required this.sourceOwner,
    required this.sourceVisitor,
  });

  final RightNowKind kind;

  /// The small caps title: `STATUS`, `LOCAL TIME`, `WHERE`, `ON PULSE SINCE`.
  final String label;

  /// The value itself, already formatted for display.
  final String value;

  /// Where this value came from, phrased for the owner of the card…
  final String sourceOwner;

  /// …and for someone else looking at it.
  final String sourceVisitor;

  String sourceFor(ProfileViewMode mode) =>
      mode.isVisitor ? sourceVisitor : sourceOwner;
}

/// The grid, derived — never stored, so it can never disagree with the profile.
class RightNowBoard {
  const RightNowBoard(this.entries);

  final List<RightNowEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// The one sentence under the grid. It is part of the design, not a tooltip:
  /// the honesty is the feature.
  static const String disclaimer =
      'Pulse only shows what someone chose to share — no GPS, '
      'no listening history, no guessed location.';

  static const int statusMax = 80;
  static const int whereMax = 40;

  /// `now` is passed in so the widget layer stays build-order independent and
  /// so tests can pin a clock.
  static RightNowBoard of({required Profile profile, required DateTime now}) {
    final entries = <RightNowEntry>[];

    final status = profile.statusText.trim();
    if (status.isNotEmpty) {
      entries.add(
        RightNowEntry(
          kind: RightNowKind.status,
          label: 'Status',
          value: status,
          sourceOwner: 'You wrote it · everyone',
          sourceVisitor: 'Written by them · everyone',
        ),
      );
    }

    final zone =
        ProfileTime.fromProfile(
          offsetMinutes: profile.utcOffsetMinutes,
          label: profile.timezone,
        ) ??
        ProfileTime.fromLocalDevice(now);
    entries.add(
      RightNowEntry(
        kind: RightNowKind.localTime,
        label: 'Local time',
        value: zone.displayAt(now),
        sourceOwner: 'From your timezone',
        sourceVisitor: 'From their timezone',
      ),
    );

    final where = profile.whereText.trim();
    if (where.isNotEmpty) {
      entries.add(
        RightNowEntry(
          kind: RightNowKind.where,
          label: 'Where',
          value: where,
          sourceOwner: 'You typed this · friends',
          sourceVisitor: 'Typed by them · friends',
        ),
      );
    }

    final joined = profile.joinedAt;
    if (joined != null) {
      entries.add(
        RightNowEntry(
          kind: RightNowKind.joined,
          label: 'On Pulse since',
          value: monthYear(joined.toLocal()),
          sourceOwner: 'From the account',
          sourceVisitor: 'From the account',
        ),
      );
    }

    return RightNowBoard(List<RightNowEntry>.unmodifiable(entries));
  }

  static const List<String> _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// `March 2024`. Spelled out rather than numeric: the card reads, it does not
  /// report.
  static String monthYear(DateTime moment) =>
      '${_months[moment.month - 1]} ${moment.year}';
}
