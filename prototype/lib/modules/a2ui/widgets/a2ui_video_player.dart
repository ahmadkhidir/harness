import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Interactive on-device video player component for A2UI surfaces.
///
/// Features:
/// - Streams remote MP4/HLS/WebM video sources natively in Flutter.
/// - In-widget Play/Pause overlay, time indicator, and scrubbable progress bar.
/// - Volume mute/unmute toggle.
/// - Auto-hiding control overlays for immersive viewing.
/// - Graceful handling of network latency, buffering, and headless test environments.
class A2UIVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool controls;
  final double? aspectRatio;

  const A2UIVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.controls = true,
    this.aspectRatio,
  });

  @override
  State<A2UIVideoPlayer> createState() => _A2UIVideoPlayerState();
}

class _A2UIVideoPlayerState extends State<A2UIVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isMuted = false;
  String? _errorMessage;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  void _initVideoPlayer() {
    final cleanUrl = widget.url.trim();
    if (cleanUrl.isEmpty) {
      setState(() => _errorMessage = 'No video URL provided.');
      return;
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https') && !uri.isScheme('file'))) {
      setState(() => _errorMessage = 'Invalid video URL: $cleanUrl');
      return;
    }

    try {
      _controller = VideoPlayerController.networkUrl(uri)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isInitialized = true;
            _errorMessage = null;
          });
          if (widget.autoPlay) {
            _controller?.play();
            _startHideControlsTimer();
          }
        }).catchError((e) {
          if (!mounted) return;
          setState(() {
            _isInitialized = false;
            _errorMessage = 'Video playback error: $e';
          });
        });

      _controller?.addListener(_onControllerUpdate);
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _errorMessage = 'Initialization notice: $e';
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_controller != null && _controller!.value.hasError) {
      setState(() {
        _errorMessage = _controller!.value.errorDescription ?? 'Video playback error.';
      });
    } else {
      setState(() {});
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _cancelHideControlsTimer();
      setState(() => _showControls = true);
    } else {
      _controller!.play();
      setState(() => _showControls = true);
      _startHideControlsTimer();
    }
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    final newMute = !_isMuted;
    _controller!.setVolume(newMute ? 0.0 : 1.0);
    setState(() => _isMuted = newMute);
  }

  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _cancelHideControlsTimer();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetAspect = widget.aspectRatio ??
        (_isInitialized && _controller != null && _controller!.value.aspectRatio > 0
            ? _controller!.value.aspectRatio
            : 16 / 9);

    if (_errorMessage != null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_camera_back_outlined, size: 36, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text(
                'Video Preview',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.url.isNotEmpty ? widget.url : 'No stream URL provided',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _initVideoPlayer,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }

    final isPlaying = _controller!.value.isPlaying;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: targetAspect,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video surface
            GestureDetector(
              onTap: _onTapVideo,
              child: VideoPlayer(_controller!),
            ),

            // Controls Overlay
            if (widget.controls && _showControls)
              Container(
                color: Colors.black38,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top header: Mute toggle
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                        ),
                        onPressed: _toggleMute,
                      ),
                    ),

                    // Center Play/Pause button
                    IconButton(
                      key: const Key('video_center_play_pause'),
                      iconSize: 52,
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayPause,
                    ),

                    // Bottom Toolbar with scrubbable progress bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller!,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            colors: VideoProgressColors(
                              playedColor: theme.colorScheme.primary,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                              IconButton(
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

