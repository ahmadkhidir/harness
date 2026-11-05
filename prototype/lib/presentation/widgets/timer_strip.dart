import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/scheduled_timer.dart';
import '../../data/services/timer_service.dart';

/// Compact, non-message indicator for scheduled self-prompt timers.
///
/// Timers never appear in the chat transcript; this strip shows pending,
/// queued, and running timers for the active session.
class TimerStrip extends StatefulWidget {
  final String sessionId;
  final TimerService? timerService;

  const TimerStrip({
    super.key,
    required this.sessionId,
    this.timerService,
  });

  @override
  State<TimerStrip> createState() => _TimerStripState();
}

class _TimerStripState extends State<TimerStrip> {
  StreamSubscription<List<ScheduledTimer>>? _subscription;
  List<ScheduledTimer> _timers = [];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TimerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.timerService != widget.timerService) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    final service = widget.timerService;
    if (service == null) return;
    _subscription = service.watch(widget.sessionId).listen((timers) {
      if (!mounted) return;
      setState(() => _timers = timers);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _remaining(ScheduledTimer timer) {
    final remaining = timer.firesAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return 'due';
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m ${remaining.inSeconds.remainder(60)}s';
    }
    return '${remaining.inSeconds}s';
  }

  String _summary() {
    if (_timers.length > 1) return '${_timers.length} scheduled timers';
    final timer = _timers.first;
    final label = timer.label?.trim();
    final name = label == null || label.isEmpty ? 'Scheduled prompt' : label;
    if (timer.status == ScheduledTimerStatus.running) {
      return '$name · running';
    }
    if (timer.status == ScheduledTimerStatus.queued) {
      return '$name · queued';
    }
    return '$name · ${_remaining(timer)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_timers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showTimerSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _summary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTimerSheet() async {
    final service = widget.timerService;
    if (service == null) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StreamBuilder<List<ScheduledTimer>>(
          stream: service.watch(widget.sessionId),
          initialData: _timers,
          builder: (context, snapshot) {
            final timers = snapshot.data ?? const <ScheduledTimer>[];
            if (timers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No scheduled timers.'),
              );
            }

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: timers.map((timer) {
                  final status = timer.status == ScheduledTimerStatus.running
                      ? 'Running'
                      : timer.status == ScheduledTimerStatus.queued
                          ? 'Queued'
                          : _remaining(timer);
                  return ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(
                      timer.label?.trim().isNotEmpty == true
                          ? timer.label!
                          : 'Scheduled prompt',
                    ),
                    subtitle: Text(
                      '${timer.prompt}\n$status',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Cancel timer',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await service.cancel(widget.sessionId, timer.id);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }
}
