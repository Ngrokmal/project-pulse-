import 'package:material_ui/material_ui.dart';

import '../../domain/explore_palette.dart';
import 'mascot_blob.dart';

/// An empty list that still says something.
///
/// Never a grey box and never a bare "No data": the mascot floats, the headline
/// names the state, the body explains what will appear here and why it is empty
/// right now, and the optional action is the one useful next step.
class ExploreEmptyState extends StatelessWidget {
  const ExploreEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.mascotSize = 128,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double mascotSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MascotBlob(size: mascotSize),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              height: 1.25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: ExplorePalette.ink,
            ),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C7890),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onAction,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: ExplorePalette.brand100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: ExplorePalette.brand500.withValues(alpha: 0.24),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ExplorePalette.brand700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
