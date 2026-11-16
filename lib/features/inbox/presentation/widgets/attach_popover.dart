import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The attach popover from the reference: it rises from the composer with a
/// spring and fades out of existence when closed. Three tiles, no ghosts — each
/// one is wired to a real action.
class AttachPopover extends StatelessWidget {
  const AttachPopover({
    super.key,
    required this.open,
    required this.onPhoto,
    required this.onFile,
    required this.onForceAudio,
  });

  final bool open;
  final VoidCallback onPhoto;
  final VoidCallback onFile;
  final VoidCallback onForceAudio;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedSlide(
          offset: open ? Offset.zero : const Offset(0, 0.12),
          duration: const Duration(milliseconds: 280),
          curve: InboxMotion.spring,
          child: AnimatedScale(
            scale: open ? 1 : 0.94,
            duration: const Duration(milliseconds: 280),
            curve: InboxMotion.spring,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: InboxPalette.hairline),
                boxShadow: InboxPalette.sheet,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Tile(
                    label: 'Photo',
                    icon: Icons.photo_camera_rounded,
                    gradient: InboxPalette.brand,
                    onTap: onPhoto,
                  ),
                  const SizedBox(width: 8),
                  _Tile(
                    label: 'File',
                    icon: Icons.folder_rounded,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7ED0C1), Color(0xFF2F9E8B)],
                    ),
                    onTap: onFile,
                  ),
                  const SizedBox(width: 8),
                  _Tile(
                    label: 'Force',
                    icon: Icons.graphic_eq_rounded,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF6C479), Color(0xFFD08A2A)],
                    ),
                    onTap: onForceAudio,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D5F3FDC),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: InboxPalette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
