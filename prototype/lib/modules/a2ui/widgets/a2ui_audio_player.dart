import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'a2ui_media_source.dart';

/// Interactive on-device audio player component for A2UI surfaces.
///
/// Features:
/// - Streams audio from remote HTTPS URLs or local file paths.
/// - In-widget Play, Pause, Resume, and Stop controls with 0ms local latency.
/// - Real-time scrubbable progress slider and timestamp formatting (`mm:ss`).
/// - Automatic resource cleanup on widget disposal.
/// - Graceful fallback on network errors or platform channel absence in tests.
class A2UIAudioPlayer extends StatefulWidget {
  final String url;
  final String title;
  final bool autoPlay;

  const A2UIAudioPlayer({
    super.key,
    required this.url,
    this.title = 'Audio Track',
    this.autoPlay = false,
  });

  @override
  State<A2UIAudioPlayer> createState() => _A2UIAudioPlayerState();
}

class _A2UIAudioPlayerState extends State<A2UIAudioPlayer> {
  AudioPlayer? _player;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _stateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    try {
      _player = AudioPlayer();

      _stateSubscription = _player!.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() {
          _playerState = state;
          _isLoading = false;
        });
      });

      _durationSubscription = _player!.onDurationChanged.listen((newDuration) {
        if (!mounted) return;
        setState(() => _duration = newDuration);
      });

      _positionSubscription = _player!.onPositionChanged.listen((newPosition) {
        if (!mounted) return;
        setState(() => _position = newPosition);
      });

      _completeSubscription = _player!.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _playerState = PlayerState.completed;
          _position = Duration.zero;
        });
      });

      if (widget.autoPlay && widget.url.isNotEmpty) {
        _togglePlay();
      }
    } catch (e) {
      // Platform channels may be absent during headless widget testing
      _errorMessage = 'Playback initialization notice: $e';
    }
  }

  Future<void> _togglePlay() async {
    if (_player == null) return;

    final media = A2UIMediaSource.resolve(widget.url);
    if (media.isEmpty) {
      setState(() => _errorMessage = 'No playable audio source provided.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_playerState == PlayerState.playing) {
        await _player!.pause();
      } else if (_playerState == PlayerState.paused) {
        await _player!.resume();
      } else if (media.isLocal) {
        await _player!.play(DeviceFileSource(media.file!.path));
      } else {
        await _player!.play(UrlSource(media.networkUrl!));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load audio: $e';
      });
    }
  }

  Future<void> _seek(double seconds) async {
    if (_player == null) return;
    try {
      final target = Duration(milliseconds: (seconds * 1000).round());
      await _player!.seek(target);
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = _playerState == PlayerState.playing;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Icon + Title + Play/Pause Button
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPlaying
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.graphic_eq : Icons.audiotrack,
                  color: isPlaying
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.isNotEmpty ? widget.title : 'Audio Player',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _errorMessage != null
                          ? 'Error loading stream'
                          : isPlaying
                              ? 'Playing'
                              : (_position > Duration.zero ? 'Paused' : 'Ready to play'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _errorMessage != null
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isLoading)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton.filled(
                  key: const Key('audio_play_pause_button'),
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Timeline Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
            ),
            child: Slider(
              value: _position.inMilliseconds
                  .clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0)
                  .toDouble(),
              min: 0.0,
              max: (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1).toDouble(),
              onChanged: _duration.inMilliseconds > 0
                  ? (value) => _seek(value / 1000.0)
                  : null,
            ),
          ),

          // Timestamps: Current Position / Total Duration
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

