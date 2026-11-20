import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_view_mode.dart';
import 'pulse_ui.dart';

/// One circle the account belongs to, as the lens needs it.
class PeopleCircle {
  const PeopleCircle({
    required this.title,
    required this.subtitle,
    required this.initials,
    this.secondInitials,
  });

  final String title;
  final String subtitle;
  final String initials;
  final String? secondInitials;
}

/// One face in the stack of people.
class PeopleFace {
  const PeopleFace({required this.initials, required this.tone});

  final String initials;

  /// 0…3 — which gradient of the four brand pairs this face wears.
  final int tone;
}

/// People: who you both know, the circles you share, and one way to bring
/// somebody in.
///
/// Everything here is read from the account's real friendships and groups; when
/// there is nothing yet the lens says so instead of inventing faces.
class PeopleLens extends StatelessWidget {
  const PeopleLens({
    super.key,
    required this.faces,
    required this.circles,
    required this.mode,
    required this.knownLine,
    required this.onOpenCode,
  });

  final List<PeopleFace> faces;
  final List<PeopleCircle> circles;
  final ProfileViewMode mode;
  final String knownLine;
  final VoidCallback onOpenCode;

  static const List<List<Color>> _tones = <List<Color>>[
    <Color>[Color(0xFF9B8AF5), Color(0xFF4F25C4)],
    <Color>[Color(0xFF9BABF6), Color(0xFF3768D2)],
    <Color>[Color(0xFFB8A2FA), Color(0xFF5F3FDC)],
    <Color>[Color(0xFF3768D2), Color(0xFF191B73)],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PulseCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _FaceStack(faces: faces),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'People you know',
                      style: AppTypography.titleMedium.copyWith(fontSize: 13.8),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      knownLine,
                      style: AppTypography.micro.copyWith(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PulseEyebrow('Circles you are in'),
        if (circles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'No group yet — every circle you join shows up here.',
              style: AppTypography.micro.copyWith(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          for (final circle in circles)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _CircleCard(circle: circle, tones: _tones),
            ),
        const SizedBox(height: 3),
        PulseRowStack(
          children: [
            PulseRow(
              icon: Icons.group_add_outlined,
              tone: PulseTone.blue,
              title: 'Bring someone in',
              subtitle: 'Share a code, they land straight here',
              trailing: const PulseChevron(icon: Icons.qr_code_2_rounded),
              onTap: onOpenCode,
            ),
          ],
        ),
      ],
    );
  }

  static List<Color> toneOf(int index) => _tones[index % _tones.length];
}

class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.faces});

  final List<PeopleFace> faces;

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.brand100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.people_outline_rounded,
          size: 20,
          color: AppColors.brand600,
        ),
      );
    }
    final shown = faces.take(4).toList(growable: false);
    const step = 21.0;
    const diameter = 40.0;
    return SizedBox(
      // The stack must be as wide as its last face, or the earlier ones get
      // clipped by the Row that holds it.
      width: diameter + (shown.length - 1) * step,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted left to right, so the first face ends up on top.
          for (final (index, face) in shown.indexed)
            Positioned(
              left: index * step,
              child: Container(
                width: diameter,
                height: diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: PeopleLens.toneOf(face.tone),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: AppColors.card, width: 2.4),
                ),
                child: Text(
                  face.initials,
                  style: AppTypography.micro.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.circle, required this.tones});

  final PeopleCircle circle;
  final List<List<Color>> tones;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      padding: const EdgeInsets.all(13),
      onTap: () => PulseToast.show(context, 'Opening ${circle.title}'),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 40,
            child: Stack(
              children: [
                _bubble(0, circle.initials, 0),
                if (circle.secondInitials != null)
                  Positioned(
                    left: 18,
                    child: _bubble(1, circle.secondInitials!, 1),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  circle.title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 13.8),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  circle.subtitle,
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const PulseChevron(),
        ],
      ),
    );
  }

  Widget _bubble(int index, String initials, int tone) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    margin: EdgeInsets.only(top: index * 8.0),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: tones[tone % tones.length]),
      border: Border.all(color: AppColors.card, width: 2),
    ),
    child: Text(
      initials,
      style: AppTypography.micro.copyWith(
        color: Colors.white,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
