import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/widgets/answer_view.dart';

void main() {
  const answer = 'Here are ideas for Somalia.\n\n'
      '### 1. WhatsApp Automation Agency (My top recommendation)\n'
      '[[GARAD_PHOTOS: WhatsApp business customer service Africa]]\n'
      'Help shops answer customers automatically.\n\n'
      '### 2. School Management App\n'
      '[[GARAD_PHOTOS: school management software]]\n'
      'One system schools pay for monthly.';

  test('each idea gets its pictures, in place, and the marker text never shows', () {
    final parts = parseAnswer(answer);
    expect(parts.whereType<PhotosPart>().map((p) => p.query), [
      'WhatsApp business customer service Africa',
      'school management software',
    ]);
    // Heading, then its pictures, then its description.
    expect(parts[1], isA<PhotosPart>());
    expect((parts[0] as TextPart).markdown, endsWith('(My top recommendation)'));
    for (final t in parts.whereType<TextPart>()) {
      expect(t.markdown, isNot(contains('GARAD')));
    }
  });

  test('while streaming, a half-written marker is hidden, not shown as text', () {
    for (final cut in ['[', '[[GAR', '[[GARAD_PHOTOS: school man', '[[GARAD_PHOTOS: school management software]']) {
      final parts = parseAnswer('### 2. School Management App\n$cut');
      expect(parts.whereType<PhotosPart>(), isEmpty, reason: cut);
      expect((parts.single as TextPart).markdown, '### 2. School Management App', reason: cut);
    }
  });

  testWidgets('shows one large and two small pictures; nothing when none are found', (tester) async {
    final asked = <String>[];
    PhotoStrip.load = (context, query) async {
      asked.add(query);
      if (query == 'nothing') return const [];
      if (query == 'one') return const [WebPhoto(url: 'https://example.com/one.jpg', title: 'One')];
      return const [
        WebPhoto(url: 'https://example.com/a.jpg', title: 'A'),
        WebPhoto(url: 'https://example.com/b.jpg', title: 'B'),
        WebPhoto(url: 'https://example.com/c.jpg', title: 'C'),
        WebPhoto(url: 'https://example.com/d.jpg', title: 'D'),
      ];
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          // The chat scrolls; so does this page (loading frames are full width).
          body: SingleChildScrollView(
            child: Column(children: [PhotoStrip(query: 'school management software'), PhotoStrip(query: 'nothing')]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(asked, ['school management software', 'nothing']);
    expect(find.bySemanticsLabel('A'), findsOneWidget);
    expect(find.bySemanticsLabel('C'), findsOneWidget);
    expect(find.bySemanticsLabel('D'), findsNothing, reason: 'three pictures at most');
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('one picture made by the AI fills the width, in a 3:2 frame', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Column(children: [PhotoStrip(query: 'one')]))),
    );
    expect(find.text('Creating image…'), findsOneWidget, reason: 'while it is being made');
    await tester.pump();
    final size = tester.getSize(find.bySemanticsLabel('One'));
    expect(size.width, 800);
    expect(size.height, closeTo(800 * 2 / 3, 1));
  });
}
