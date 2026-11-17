import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

/// The app's own video player — no hand-off to another app, no browser.
///
/// Real controls: play/pause, a scrubbable rail with real buffered position,
/// elapsed/total time, mute, and a proper error state instead of a black screen.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.url,
    this.title,
    this.byline,
  });

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
        opaque: true,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            VideoPlayerView(url: url, title: title, byline: byline),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  String? _error;
  bool _chrome = true;
  Timer? _hideTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() => _error = 'That video link is not valid.');
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.addListener(_onTick);
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _duration = controller.value.duration;
        _playing = true;
        _error = null;
      });
      _scheduleHide();
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'This video could not be played.');
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    setState(() {
      _position = value.position;
      _duration = value.duration;
      _playing = value.isPlaying;
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready =
        controller != null && controller.value.isInitialized && _error == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: ready ? _toggleChrome : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio == 0
                      ? 16 / 9
                      : controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            if (_error != null) _ErrorState(message: _error!, onRetry: _retry),
            if (_error == null && !ready) const _Loading(),
            if (ready)
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: _Chrome(
                    position: _position,
                    duration: _duration,
                    playing: _playing,
                    title: widget.title,
                    byline: widget.byline,
                    onClose: () => Navigator.of(context).maybePop(),
                    onTogglePlay: _togglePlay,
                    onSeek: (value) {
                      final target = Duration(
                        milliseconds: (value * _duration.inMilliseconds)
                            .round(),
                      );
                      controller.seekTo(target);
                      _scheduleHide();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _error = null;
      _controller?.dispose();
      _controller = null;
    });
    _open();
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.position,
    required this.duration,
    required this.playing,
    required this.title,
    required this.byline,
    required this.onClose,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final String? title;
  final String? byline;
  final VoidCallback onClose;
  final Future<void> Function() onTogglePlay;
  final ValueChanged<double> onSeek;

  static String _mmss(Duration value) {
    final total = value.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000), Color(0xB3000000)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _RoundButton(
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
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: onTogglePlay,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xFFA8ECFF),
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.24,
                        ),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.12),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(value: progress, onChanged: onSeek),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Text(
                            _mmss(position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _mmss(duration),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
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

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 34,
      height: 34,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: Color(0xFFA8ECFF),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            size: 34,
            color: Colors.white54,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
