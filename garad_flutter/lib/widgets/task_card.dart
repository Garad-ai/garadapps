import 'package:flutter/material.dart';

import '../api/models.dart';
import '../schedule_strings.dart';
import '../theme.dart';

/// A scheduled task in chat, ChatGPT-style: one small pill, "Scheduled · Drink water · 2:59 PM"
/// (or "Completed · Drink water" once it fired). Tap to open the task.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onOpen});

  final ScheduledTask task;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = scheduleStrings;
    final when = task.nextRunAt;
    final status = s.statuses[task.status] ?? task.status;
    final time = task.recurring ? task.schedule : (when != null && task.status == 'active' ? clockTime(when) : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: c.surfaceStrong,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: status,
                      style: TextStyle(color: task.status == 'failed' ? c.danger : c.muted),
                    ),
                    TextSpan(
                      text: '  ·  ',
                      style: TextStyle(color: c.faint),
                    ),
                    TextSpan(
                      text: task.title,
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w500),
                    ),
                    if (time != null)
                      TextSpan(
                        text: '  ·  $time',
                        style: TextStyle(color: c.muted),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
