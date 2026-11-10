import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/document_screen.dart';
import 'package:garad_ai/widgets/answer_view.dart';
import 'package:provider/provider.dart';

/// A real "make pdf" answer as the website saves it.
const pdfAnswer =
    "I've prepared **Online Business Idea: Business Plan** as a professional PDF document.\n\n"
    '<div class="garad-tool-result-card garad-artifact-result-card" data-mime-type="application/pdf" '
    'data-extension="pdf" data-kind="pdf" data-size="887058"><strong>PDF created</strong>'
    '<span>online-business-idea-business-plan.pdf</span><a href="http://localhost/garad.ai/public/dashboard/user/openai/chat/pro/artifacts/1/download" '
    'target="_blank" rel="noopener">Open / Download PDF</a></div>Your business plan PDF is ready.';

Widget host(ChatMessage message, {bool streaming = false, ValueChanged<String>? onChoose}) =>
    ChangeNotifierProvider.value(
      value: AuthState(GaradApi()),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnswerView(message: message, streaming: streaming, onChoose: onChoose),
          ),
        ),
      ),
    );

void main() {
  test('a PDF answer becomes text, a file card, then text', () {
    final parts = parseAnswer(pdfAnswer);
    expect(parts, hasLength(3));
    final file = parts[1] as FilePart;
    expect(file.name, 'online-business-idea-business-plan.pdf');
    expect(file.kind, 'pdf');
    expect(file.size, 887058);
    expect(file.url, endsWith('/artifacts/1/download'));
  });

  test('an image marker becomes an image', () {
    final encoded = base64Url.encode(utf8.encode('https://garad.ai/uploads/logo.png')).replaceAll('=', '');
    final parts = parseAnswer('Image created successfully.\n\n[[GARAD_IMAGE_RESULT:$encoded]]');
    expect((parts.last as ImagePart).url, 'https://garad.ai/uploads/logo.png');
  });

  testWidgets('the PDF shows as a card, not raw HTML', (tester) async {
    await tester.pumpWidget(host(ChatMessage(role: 'assistant', content: pdfAnswer)));
    expect(find.text('online-business-idea-business-plan.pdf'), findsOneWidget);
    expect(find.text('PDF · 867 KB'), findsOneWidget);
    expect(find.textContaining('<div'), findsNothing);
  });

  testWidgets('a question shows its options; tapping one answers it', (tester) async {
    String? picked;
    const answer =
        'Which kind of document do you want?\n\n```garad-choices\n'
        '{"question":"What should the document be?","options":['
        '{"label":"Pick an idea for me (Recommended)","description":"I choose a promising idea"},'
        '{"label":"I have an idea","description":"You tell me the idea"}]}\n```';
    await tester.pumpWidget(host(ChatMessage(role: 'assistant', content: answer), onChoose: (a) => picked = a));

    expect(find.text('What should the document be?'), findsOneWidget);
    expect(find.textContaining('garad-choices'), findsNothing);
    await tester.tap(find.text('I have an idea'));
    expect(picked, 'I have an idea');
  });

  testWidgets('while creating a PDF it shows a document placeholder, not the typing spinner', (tester) async {
    final message = ChatMessage(role: 'assistant', content: '')
      ..activity = const ToolStatus(tool: 'create_pdf', state: 'working', label: 'Creating PDF…');
    await tester.pumpWidget(host(message, streaming: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Preparing your document…'), findsOneWidget);
    expect(find.byType(DocumentThumb), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('before anything arrives it says Thinking…', (tester) async {
    await tester.pumpWidget(host(ChatMessage(role: 'assistant', content: ''), streaming: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thinking…'), findsOneWidget);
  });
}
