import 'dart:async';

import 'package:flutter/material.dart';

import '../api/work_steps.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// Claude's document engine steps while Garad builds a file (slides, Word, PDF), as garad.ai shows
/// them (frontend/src/core/WorkStepsPanel.tsx). While it works: four pulsing dots, the current step and
/// the time ("Running a command 11s ›"). Afterwards a grey summary ("Ran a command, created a file,
/// shared files ›"). Either opens into the list of steps; a step with a command or note opens to show it.
class WorkStepsView extends StatefulWidget {
  const WorkStepsView({super.key, required this.steps, required this.working, this.since});

  final List<WorkStep> steps;
  final bool working;

  /// When the reply started (one clock for the whole reply); the first step's start when unknown.
  final DateTime? since;

  @override
  State<WorkStepsView> createState() => _WorkStepsViewState();
}

class _WorkStepsViewState extends State<WorkStepsView> {
  bool _open = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(WorkStepsView old) {
    super.didUpdateWidget(old);
    if (old.working != widget.working) _tick();
  }

  /// Re-reads the line every second while working (the timer, and "Reading a file" → "Creating a file").
  void _tick() {
    _clock?.cancel();
    _clock = widget.working ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {})) : null;
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final somali = chatStrings.isSomali;
    final now = DateTime.now();
    final start = widget.since ??
        widget.steps.map((s) => s.startedAt).whereType<DateTime>().fold<DateTime?>(
          null,
          (a, b) => a == null || b.isBefore(a) ? b : a,
        ) ??
        now;
    final line = widget.working
        ? workLiveLine(widget.steps, somali: somali, now: now)
        : workSummary(widget.steps, somali: somali);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.working) ...[const WorkingDots(), const SizedBox(width: 9)],
                  Flexible(
                    child: Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 15),
                    ),
                  ),
                  if (widget.working) ...[
                    const SizedBox(width: 8),
                    Text(
                      formatElapsed(now.difference(start)),
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: c.faint),
                ],
              ),
            ),
          ),
          if (_open && widget.steps.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < widget.steps.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.line),
                    _StepRow(step: widget.steps[i], somali: somali, now: now),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({required this.step, required this.somali, required this.now});

  final WorkStep step;
  final bool somali;
  final DateTime now;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final step = widget.step;
    final canOpen = step.detail != null && !const {'read', 'view', 'present'}.contains(step.kind);
    final title = Row(
      children: [
        Flexible(
          child: Text(
            workStepTitle(step, somali: widget.somali, now: widget.now),
            style: TextStyle(color: step.running ? c.text : c.muted, fontSize: 14.5),
          ),
        ),
        if (step.file != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              step.file!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.faint, fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ],
        if (canOpen) ...[
          const Spacer(),
          Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: c.faint),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: canOpen ? () => setState(() => _open = !_open) : null,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: title),
        ),
        if (_open && step.detail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: step.kind == 'note'
                ? Text(step.detail!, style: TextStyle(color: c.muted, fontSize: 14, height: 1.45))
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.surfaceStrong, borderRadius: BorderRadius.circular(10)),
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        step.detail!,
                        style: TextStyle(color: c.text, fontSize: 12.5, height: 1.4, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// garad.ai's working icon: four small dots in a square that pulse in turn (work-steps-pulse, 1.2 s).
class WorkingDots extends StatefulWidget {
  const WorkingDots({super.key});

  @override
  State<WorkingDots> createState() => _WorkingDotsState();
}

class _WorkingDotsState extends State<WorkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  // The website's delays, in grid order (top-left, top-right, bottom-left, bottom-right): 0, .3, .9, .6 s.
  static const _delays = [0.0, 0.25, 0.75, 0.5];

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = Palette.of(context).brand;
    if (MediaQuery.of(context).disableAnimations) {
      return _grid((_) => (0.8, 1.0), brand);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => _grid((i) {
        // ease-in-out between 25% and 100% opacity, peaking halfway through each dot's cycle.
        final t = (_pulse.value - _delays[i]) % 1.0;
        final wave = Curves.easeInOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2);
        return (0.25 + 0.75 * wave, 0.8 + 0.2 * wave);
      }, brand),
    );
  }

  Widget _grid((double, double) Function(int) look, Color color) {
    Widget dot(int i) {
      final (opacity, scale) = look(i);
      return Transform.scale(
        scale: scale,
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color.withValues(alpha: opacity), shape: BoxShape.circle),
        ),
      );
    }

    return SizedBox(
      width: 13,
      height: 13,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [dot(0), dot(1)]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [dot(2), dot(3)]),
        ],
      ),
    );
  }
}
