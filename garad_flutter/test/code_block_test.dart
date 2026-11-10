import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/widgets/answer_view.dart';
import 'package:garad_ai/widgets/code_block.dart';

void main() {
  test('code fences become code cards; unfinished ones are marked not done', () {
    final parts = parseAnswer('Your first program:\n\n```python\nprint("Hello")\n```\n\nThat prints Hello.\n\n```js\nconsole.log(1)');
    final code = parts.whereType<CodePart>().toList();
    expect(code.map((c) => c.language), ['python', 'js']);
    expect(code.first.code, 'print("Hello")');
    expect(code.first.done, isTrue);
    expect(code.last.done, isFalse, reason: 'still being written: no Run yet');
    expect(parts.whereType<TextPart>().map((t) => t.markdown), ['Your first program:', 'That prints Hello.']);
  });

  test('a long example is cut into its parts, each with its title and its own card', () {
    const answer = 'All the basics:\n\n```python\n'
        'import math\n\n'
        '# ===== 1. Variables and Data Types =====\nname = "Amina"\nage = 25\n\n'
        '# ===== 2. Operators =====\na, b = 10, 3\nprint("Sum:", a + b)\n\n'
        '# ===== 3. Control Flow =====\nif age >= 18:\n    print(name, "is an adult")\n```';
    final parts = parseAnswer(answer);
    final cards = parts.whereType<CodePart>().toList();
    expect(cards.map((c) => c.code), [
      'import math',
      'name = "Amina"\nage = 25',
      'a, b = 10, 3\nprint("Sum:", a + b)',
      'if age >= 18:\n    print(name, "is an adult")',
    ]);
    expect(parts.whereType<TextPart>().map((t) => t.markdown), [
      'All the basics:',
      '#### 1. Variables and Data Types',
      '#### 2. Operators',
      '#### 3. Control Flow',
    ]);
    // Part 3 uses name and age from part 1: the earlier parts run (silently) first.
    expect(cards.last.setup, ['import math', 'name = "Amina"\nage = 25', 'a, b = 10, 3\nprint("Sum:", a + b)']);
    expect(cards.every((c) => c.done), isTrue);
  });

  test('one section comment alone does not cut the code', () {
    expect(splitCodeSections('# ===== Setup =====\nx = 1'), hasLength(1));
  });

  test('the website\'s own blocks stay as before', () {
    final parts = parseAnswer('```garad-steps\n{"title":"x","steps":[]}\n```');
    expect(parts.single, isA<TextPart>());
  });

  test('the run page keeps the code inside its script', () {
    final page = codeRunPage('python', 'print("</script><b>hi</b>")', '7');
    expect(page.contains('</script><b>'), isFalse);
    expect(page, contains('pyodide/v0.26.4/full/pyodide.js'));
    expect(codeRunPage('javascript', 'console.log(1)', '7'), isNot(contains('pyodide')));
  });

  test('a Python error shows the learner\'s lines, not Pyodide\'s', () {
    const raw = 'Traceback (most recent call last):\n'
        '  File "/lib/python311.zip/_pyodide/_base.py", line 573, in eval_code_async\n'
        '    await CodeRunner(\n'
        '  File "<exec>", line 1, in <module>\n'
        'ZeroDivisionError: division by zero';
    expect(cleanTraceback(raw), 'Traceback (most recent call last):\n  File "<exec>", line 1, in <module>\nZeroDivisionError: division by zero');
  });

  testWidgets('Run shows the output under the code, ChatGPT-style', (tester) async {
    void Function(String)? deliver;
    String? ranPage;
    CodeBlock.runnerBuilder = (page, onMessage) {
      ranPage = page;
      deliver = onMessage;
      return const SizedBox();
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CodeBlock(language: 'python', code: 'print("Hello, world!")')),
        ),
      ),
    );
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Output'), findsNothing);

    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(ranPage, contains('print(\\"Hello, world!\\")'));
    expect(find.text('Running the code…'), findsOneWidget);

    final id = RegExp(r'var RUN_ID = "(\d+)"').firstMatch(ranPage!)!.group(1);
    String msg(String kind, String text) => jsonEncode({'id': id, 'kind': kind, 'text': text});
    deliver!(jsonEncode({'id': 'other', 'kind': 'out', 'text': 'not mine'}));
    deliver!(msg('out', 'Hello, world!'));
    deliver!(msg('done', ''));
    await tester.pump();

    expect(find.text('Output'), findsOneWidget);
    expect(find.textContaining('Hello, world!', findRichText: true), findsWidgets);
    expect(find.textContaining('not mine', findRichText: true), findsNothing, reason: 'another card\'s run');
    expect(find.text('Running the code…'), findsNothing);
    expect(find.text('Run'), findsOneWidget, reason: 'can run again');
  });

  testWidgets('code still being written has Copy but no Run', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodeBlock(language: 'python', code: 'print(1)', done: false)),
      ),
    );
    expect(find.text('Run'), findsNothing);
    expect(find.byTooltip('Copy code'), findsOneWidget);
  });
}
