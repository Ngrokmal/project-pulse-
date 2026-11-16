import 'package:material_ui/material_ui.dart';

import '../../application/inbox_audio_level.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import 'inbox_pressable.dart';

/// The 46 px send button.
///
/// While recording it wears the mic badge and a bloom that follows the live
/// level (`0 0 (lvl*18)px rgba(brand, lvl*.8)`); while a take uploads it shows a
/// spinner at 55 % opacity instead of pretending the send is instant.
class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.onTap,
    required this.level,
    required this.recording,
    required this.busy,
  });

  final VoidCallback? onTap;
  final InboxAudioLevel level;
  final bool recording;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: level,
      builder: (context, child) {
        final lvl = recording ? level.value : 0.0;
        return InboxPressable(
          onTap: busy ? null : onTap,
          semanticLabel: recording ? 'Send voice note' : 'Send message',
          child: AnimatedOpacity(
            opacity: busy ? 0.55 : 1,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: InboxMotion.composeHeight,
              height: InboxMotion.composeHeight,
              decoration: BoxDecoration(
                gradient: InboxPalette.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  ...InboxPalette.send,
                  if (lvl > 0.01)
                    BoxShadow(
                      color: InboxPalette.brandAlpha(
                        InboxMotion.sendBloomAlpha(lvl),
                      ),
                      blurRadius: InboxMotion.sendBloom(lvl),
                    ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  if (recording && !busy)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: InboxPalette.brand600,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          size: 9,
                          color: InboxPalette.brand600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
