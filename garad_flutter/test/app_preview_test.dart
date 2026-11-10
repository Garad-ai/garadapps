import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/chat_strings.dart';
import 'package:garad_ai/screens/app_preview_screen.dart';
import 'package:garad_ai/widgets/answer_view.dart';

/// A real "build me a website" answer: one sentence, the page, then notes.
const page =
    '<!DOCTYPE html>\n<html>\n<head>\n<title>Hodan Coffee</title>\n</head>\n<body>\n<h1>Hodan Coffee</h1>\n</body>\n</html>';
const websiteAnswer = "Here's your coffee shop website.\n\n```html\n$page\n```\n\n- A hero, menu and contact section";

const reactApp =
    'import { useState } from "react";\n\nexport default function BudgetTracker() {\n'
    '  const [items] = useState([]);\n  return <div className="p-4">{items.length}</div>;\n}';

Widget host(String content, {bool streaming = false, ValueChanged<String>? onAppChange}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: AnswerView(
        message: ChatMessage(role: 'assistant', content: content),
        streaming: streaming,
        onAppChange: onAppChange,
      ),
    ),
  ),
);

void main() {
  // No web view in tests: the preview reports an error when asked to, so "Fix it" can be tested.
  var reportError = false;
  setUp(() {
    reportError = false;
    AppPreviewScreen.previewBuilder = (page, onError, key) {
      if (reportError) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onError('Uncaught ReferenceError: total is not defined'));
      }
      return Text('running app', key: key);
    };
  });

  group('finding apps in an answer', () {
    test('a whole HTML page becomes an app with its <title>; the text around it stays', () {
      final parts = parseAnswer(websiteAnswer);
      expect(parts.map((p) => p.runtimeType), [TextPart, AppPart, TextPart]);
      final app = parts[1] as AppPart;
      expect(app.title, 'Hodan Coffee');
      expect(app.react, isFalse);
      expect(app.done, isTrue);
      expect(app.source, page);
    });

    test('a React component becomes an app named after the component', () {
      final app = parseAnswer('Done!\n\n```jsx\n$reactApp\n```').whereType<AppPart>().single;
      expect(app.react, isTrue);
      expect(app.title, 'Budget Tracker');
    });

    test('while the code is still coming, the app is not done and counts its lines', () {
      final app = parseAnswer("Here's your site.\n\n```html\n<!DOCTYPE html>\n<html>\n<head>")
          .whereType<AppPart>()
          .single;
      expect(app.done, isFalse);
      expect(app.lines, 3);
    });

    test('short code examples stay code, not apps', () {
      final parts = parseAnswer('Use a button:\n\n```html\n<button>Hi</button>\n```');
      expect(parts.whereType<AppPart>(), isEmpty);
      // A code card instead (Copy, no Run for HTML).
      final code = parts.last as CodePart;
      expect(code.language, 'html');
      expect(code.code, '<button>Hi</button>');
    });

    test('appTitleIn finds the app for version numbers', () {
      expect(appTitleIn(websiteAnswer), 'Hodan Coffee');
      expect(appTitleIn('Just text'), isNull);
    });
  });

  group('preview pages', () {
    test('the React code cannot close the page\'s <script> tag', () {
      final html = reactPreviewPage('export default function A() { return "</script><b>x</b>"; }');
      expect('<script'.allMatches(html).length, '</script>'.allMatches(html).length);
      expect(html, contains("${String.fromCharCode(92)}x3c/script>"));
      expect(html, contains('react@18.3.1'));
    });

    test('an HTML page gets the error reporter inside its <head>', () {
      final html = htmlPreviewPage(page);
      expect(html.indexOf('garadAppError'), greaterThan(html.indexOf('<head>')));
      expect(html, contains('<h1>Hodan Coffee</h1>'));
    });
  });

  testWidgets('while writing: "Building…" with the line count, then a card that opens the app', (tester) async {
    await tester.pumpWidget(host("Here's your site.\n\n```html\n<!DOCTYPE html>\n<html>\n<head>", streaming: true));
    expect(find.text(chatStrings.buildingApp), findsOneWidget);
    expect(find.text(chatStrings.writingCode(3)), findsOneWidget);
    expect(find.text('<head>'), findsOneWidget, reason: 'the line being written');

    await tester.pumpWidget(host(websiteAnswer));
    expect(find.text('Hodan Coffee'), findsOneWidget);
    expect(find.text(chatStrings.websiteKind), findsOneWidget);
    expect(find.textContaining('<!DOCTYPE'), findsNothing, reason: 'no wall of code in the chat');
  });

  testWidgets('open the app, look at the code, and ask for a change (vibe coding)', (tester) async {
    String? sent;
    await tester.pumpWidget(host(websiteAnswer, onAppChange: (change) => sent = change));
    await tester.tap(find.text('Hodan Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('running app'), findsOneWidget);

    await tester.tap(find.text(chatStrings.code));
    await tester.pumpAndSettle();
    expect(find.textContaining('<h1>Hodan Coffee</h1>'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Make the header dark green');
    await tester.pump();
    await tester.tap(find.byTooltip(chatStrings.send));
    await tester.pumpAndSettle();
    expect(sent, 'Make the header dark green');
    expect(find.text('running app'), findsNothing, reason: 'back in the chat');
  });

  testWidgets('when the app hits an error, Fix it asks Garad to fix that error', (tester) async {
    reportError = true;
    String? sent;
    await tester.pumpWidget(host(websiteAnswer, onAppChange: (change) => sent = change));
    await tester.tap(find.text('Hodan Coffee'));
    await tester.pumpAndSettle();
    expect(find.text(chatStrings.appError), findsOneWidget);

    await tester.tap(find.text(chatStrings.fixIt));
    await tester.pumpAndSettle();
    expect(sent, chatStrings.fixAppError('Uncaught ReferenceError: total is not defined'));
  });
}
