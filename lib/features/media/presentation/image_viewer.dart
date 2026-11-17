import 'package:material_ui/material_ui.dart';

/// Full-screen photo viewer: pinch to zoom, drag down to dismiss.
///
/// It is a real viewer, not a bigger bubble — black stage, no chrome until you
/// touch it, and the original file name on the top bar so you always know what
/// you are looking at.
class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.url, this.title, this.byline});

  final String url;
  final String? title;
  final String? byline;

  static Future<void> show(
    BuildContext context, {
    required String url,
    String? title,
    String? byline,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            ImageViewer(url: url, title: title, byline: byline),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  double _drag = 0;
  bool _chrome = true;

  @override
  Widget build(BuildContext context) {
    final progress = (_drag.abs() / 260).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragUpdate: (details) =>
            setState(() => _drag += details.delta.dy),
        onVerticalDragEnd: (details) {
          final flung = (details.primaryVelocity ?? 0) > 700;
          if (_drag > 110 || flung) {
            Navigator.of(context).maybePop();
            return;
          }
          setState(() => _drag = 0);
        },
        onTap: () => setState(() => _chrome = !_chrome),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.94 * (1 - progress * 0.35)),
          child: Stack(
            children: [
              Center(
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: Transform.scale(
                    scale: 1 - progress * 0.12,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _Photo(url: widget.url),
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  child: Column(
                    children: [
                      _TopBar(
                        title: widget.title,
                        byline: widget.byline,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      if (widget.byline != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Text(
                            widget.byline!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loading) {
        if (loading == null) return child;
        final total = loading.expectedTotalBytes;
        return SizedBox(
          width: 120,
          height: 120,
          child: Center(
            child: CircularProgressIndicator(
              value: total == null
                  ? null
                  : loading.cumulativeBytesLoaded / total,
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              'This photo could not be loaded.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.byline,
    required this.onClose,
  });

  final String? title;
  final String? byline;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          _GlassButton(
            icon: Icons.close_rounded,
            label: 'Close',
            onTap: onClose,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (byline != null)
                  Text(
                    byline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      ),
    );
  }
}
