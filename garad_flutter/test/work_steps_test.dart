import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/widgets/work_steps_view.dart';

/// While Garad builds slides, the app shows garad.ai's step line and summary, not just "Thinking…".
void main() {
  final t0 = DateTime(2026, 11, 26, 15, 0, 0);

  void merge(List<WorkStep> steps, Map<String, dynamic> raw, DateTime now) =>
      mergeWorkStep(steps, WorkStep.fromJson(raw)!, raw, now);

  test('steps are added, then updated by id with only what changed', () {
    final steps = <WorkStep>[];
    merge(steps, {'id': 'a', 'kind': 'command', 'state': 'running', 'detail': 'node build.js'}, t0);
    merge(steps, {'id': 'b', 'kind': 'file', 'state': 'running'}, t0.add(const Duration(seconds: 2)));
    merge(steps, {'id': 'a', 'state': 'done'}, t0.add(const Duration(seconds: 5)));

    expect(steps.map((s) => s.id), ['a', 'b']);
    expect(steps[0].running, isFalse);
    expect(steps[0].kind, 'command', reason: 'an update without a kind keeps it');
    expect(steps[0].detail, 'node build.js');
    expect(steps[0].doneAt, t0.add(const Duration(seconds: 5)));
    expect(WorkStep.fromJson({'kind': 'command'}), isNull, reason: 'no id');
    expect(WorkStep.fromJson({'id': 'x', 'kind': 'nonsense'})!.kind, 'command');
  });

  test('the live line and the summary read like the website', () {
    final steps = <WorkStep>[];
    merge(steps, {'id': 'a', 'kind': 'command', 'state': 'running'}, t0);
    expect(workLiveLine(steps, somali: false, now: t0), 'Running a command');

    merge(steps, {'id': 'a', 'state': 'done'}, t0);
    merge(steps, {'id': 'f', 'kind': 'file', 'state': 'running'}, t0);
    expect(workLiveLine(steps, somali: false, now: t0.add(const Duration(seconds: 1))), 'Reading a file');
    expect(workLiveLine(steps, somali: false, now: t0.add(const Duration(seconds: 10))), 'Creating a file');

    merge(steps, {'id': 'f', 'state': 'done'}, t0);
    merge(steps, {'id': 'c2', 'kind': 'command', 'state': 'done'}, t0);
    merge(steps, {'id': 'present', 'kind': 'present', 'state': 'done'}, t0);
    expect(workLiveLine(steps, somali: false, now: t0), 'Thinking');
    expect(workSummary(steps, somali: false), 'Ran 2 commands, read a file, shared files');
    expect(workSummary(steps, somali: true), '2 amar ayaan fuliyay, fayl ayaan akhriyay, faylal ayaan wadaagay');

    // Claude's own progress line wins over the generic one.
    merge(steps, {'id': 'w', 'kind': 'command', 'state': 'running', 'title': 'Building the slides'}, t0);
    expect(workLiveLine(steps, somali: false, now: t0), 'Building the slides');
  });

  test('the clock reads like the website', () {
    expect(formatElapsed(const Duration(seconds: 11)), '11s');
    expect(formatElapsed(const Duration(seconds: 99)), '1m 39s');
  });

  test('saved answers keep their steps, all finished', () {
    final message = ChatMessage.fromJson({
      'id': 1,
      'role': 'assistant',
      'content': 'Here is your deck.',
      'work_steps': [
        {'id': 'a', 'kind': 'command', 'state': 'running'},
        {'id': 'present', 'kind': 'present', 'state': 'done'},
        'junk',
      ],
    });
    expect(message.workSteps.length, 2);
    expect(message.workSteps.every((s) => !s.running), isTrue);
  });

  test('a PowerPoint card is a presentation, whatever the server calls it', () {
    expect(documentKind('pptx'), 'presentation');
    expect(documentKind('', extension: 'pptx'), 'presentation');
    expect(documentKind('', name: 'online-store-business-somalia.pptx'), 'presentation');
    expect(documentKind('docx'), 'document');
    expect(documentKind('presentation'), 'presentation');
    expect(documentKind('pdf'), 'pdf');
    expect(documentKind('xlsx'), 'spreadsheet');
    expect(documentKind(''), 'document');
  });

  testWidgets('working: dots, the step and the time; done: the summary', (tester) async {
    final steps = <WorkStep>[];
    final start = DateTime.now().subtract(const Duration(seconds: 11));
    mergeWorkStep(steps, WorkStep.fromJson({'id': 'a', 'kind': 'command', 'state': 'running'})!, {'state': 'running'}, start);

    Widget view(bool working) => MaterialApp(
      home: Scaffold(body: WorkStepsView(steps: steps, working: working, since: start)),
    );

    await tester.pumpWidget(view(true));
    expect(find.byType(WorkingDots), findsOneWidget);
    expect(find.text('Running a command'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1[12]s$')), findsOneWidget);

    steps.first.running = false;
    await tester.pumpWidget(view(false));
    expect(find.byType(WorkingDots), findsNothing);
    expect(find.text('Ran a command'), findsOneWidget);

    // Opens into the list of steps.
    await tester.tap(find.text('Ran a command'));
    await tester.pumpAndSettle();
    expect(find.text('Ran a command'), findsNWidgets(2));
  });
}
