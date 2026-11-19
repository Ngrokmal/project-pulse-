import 'package:material_ui/material_ui.dart';

import '../../../presence/domain/presence.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/person.dart';
import 'sparkle_burst.dart';

enum FriendAvatarRing {
  /// Nothing — a plain rounded tile.
  none,

  /// A white 2 px gap and a green 2.5 px ring: this person is in my circle.
  friend,
}

/// The avatar: gradient + initials, a photo when there is one, an honest
/// presence dot, and an optional ring for friendships.
///
/// The photo is decoded at the size it is drawn (`cacheWidth`), which is the
/// difference between a smooth list and a janky one on a slow phone.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.person,
    this.size = ExploreMotion.avatarSize,
    this.showPresence = true,
    this.ring = FriendAvatarRing.none,
    this.sparkles,
  });

  final Person person;
  final double size;
  final bool showPresence;
  final FriendAvatarRing ring;

  /// When provided, the avatar accepts sparkle bursts (the accept moment).
  final SparkleController? sparkles;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.32;
    final online = person.presence.isOnlineAt(DateTime.now());
    final dot = size * 0.27;

    Widget tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: ExplorePalette.avatarFor(person.gradientSeed),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ring == FriendAvatarRing.friend
            ? const <BoxShadow>[
                BoxShadow(color: Color(0xFFFFFFFF), spreadRadius: 2),
                BoxShadow(
                  color: Color(0x8017C653),
                  blurRadius: 8,
                  spreadRadius: 3.5,
                ),
              ]
            : ExplorePalette.avatar,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _AvatarFill(person: person, size: size),
    );

    if (showPresence && online) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: ExplorePalette.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: dot * 0.19),
              ),
            ),
          ),
        ],
      );
    }

    final burst = sparkles;
    if (burst == null) return tile;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The sparks leave the avatar and travel past its edge, so the burst
          // is drawn in a box 2.2x the avatar and centred on it. (A negative
          // Padding — the obvious way to do this — asserts at layout time.)
          Positioned.fill(
            child: OverflowBox(
              maxWidth: size * 2.2,
              maxHeight: size * 2.2,
              child: SparkleBurst(controller: burst),
            ),
          ),
          tile,
        ],
      ),
    );
  }
}

class _AvatarFill extends StatelessWidget {
  const _AvatarFill({required this.person, required this.size});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = person.avatarUrl;
    if (url == null || url.isEmpty) {
      return Text(
        person.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.31,
          height: 1,
          letterSpacing: 0.2,
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * dpr).round(),
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => Text(
        person.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.31,
          height: 1,
        ),
      ),
    );
  }
}

/// `online` / `last seen …`, in the app's existing words.
String presenceLabel(Person person, {DateTime? now}) =>
    person.presence.label(now ?? DateTime.now());

/// True when the dot should pulse — kept next to the label so the two agree.
bool presenceIsOnline(Person person) =>
    person.presence.isOnlineAt(DateTime.now()) &&
    person.presence != Presence.unknown;
