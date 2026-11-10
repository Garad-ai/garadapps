import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/screens/image_edit_screen.dart';
import 'package:garad_ai/screens/library_screen.dart';
import 'package:garad_ai/widgets/answer_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('the mask is transparent where painted and opaque elsewhere', (tester) async {
    await tester.runAsync(() async {
      // A stroke across the middle of a 200x100 picture.
      final png = await editMask(const Size(200, 100), [
        [const Offset(40, 50), const Offset(160, 50)],
      ], 20);
      final image = await decodeImageFromList(png!);
      expect([image.width, image.height], [200, 100], reason: 'the same size as the picture');
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int alpha(int x, int y) => pixels.getUint8((y * 200 + x) * 4 + 3);
      expect(alpha(100, 50), 0, reason: 'painted: change here');
      expect(alpha(100, 5), 255, reason: 'not painted: keep');
      expect(alpha(5, 50), 255, reason: 'beyond the stroke: keep');
    });
  });


  /// A screen with one button that runs [tool] on the banner and keeps what it returned.
  Future<ImageEditRequest? Function()> openTool(WidgetTester tester, ImageTool tool) async {
    ImageEditRequest? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await runImageTool(context, 'https://garad.ai/uploads/banner.png', tool),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  final send = find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded);

  testWidgets('Edit: describe a change to the whole picture', (tester) async {
    final result = await openTool(tester, ImageTool.edit);
    expect(tester.widget<IconButton>(send).onPressed, isNull, reason: 'nothing described yet');

    await tester.enterText(find.byType(TextField), 'Make the background blue');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(result()?.instruction, 'Make the background blue');
    expect(result()?.edit.imageUrl, 'https://garad.ai/uploads/banner.png');
    expect(result()?.edit.mask, isNull, reason: 'the whole picture');
  });

  testWidgets('Remove: paint over something; no words needed', (tester) async {
    final result = await openTool(tester, ImageTool.remove);
    expect(tester.widget<IconButton>(send).onPressed, isNull, reason: 'nothing painted yet');

    // Paint across the picture.
    final picture = tester.getCenter(find.byKey(const ValueKey('image-brush')));
    await tester.dragFrom(picture, const Offset(60, 0));
    await tester.pump();
    await tester.tap(send);
    // The mask is drawn off-screen (real async), then the screen closes.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(result()?.instruction, 'Remove what I painted over and fill the space so it blends in naturally.');
    expect(result()?.edit.mask, isNotNull, reason: 'the painted area goes with it');
  });

  testWidgets('Resize: pick a shape', (tester) async {
    final result = await openTool(tester, ImageTool.resize);
    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();

    expect(result()?.instruction, 'Change it to a portrait format.');
    expect(result()?.edit.size, '1024x1536');
  });

  testWidgets('the image view shows Edit · Resize · Markup · Remove and runs the tapped one', (tester) async {
    (LibraryImage, ImageTool)? ran;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImageViewer(
                  images: const [LibraryImage(id: 'b', url: 'https://garad.ai/uploads/banner.png', prompt: '')],
                  onTool: (image, tool) => ran = (image, tool),
                ),
              ),
            ),
            child: const Text('view'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('view'));
    await tester.pumpAndSettle();

    for (final label in ['Edit', 'Resize', 'Markup', 'Remove', 'Share']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Markup'));
    await tester.pumpAndSettle();
    expect(ran?.$2, ImageTool.markup);
    expect(ran?.$1.url, 'https://garad.ai/uploads/banner.png');
    expect(find.text('Markup'), findsNothing, reason: 'the image view closed');
  });

  testWidgets('an image in an answer has an Edit pill that opens Edit for it', (tester) async {
    (String, ImageTool)? edited;
    final url = 'https://garad.ai/uploads/banner.png';
    final marker = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerView(
            message: ChatMessage(role: 'assistant', content: 'Here it is.\n\n[[GARAD_IMAGE_RESULT:$marker]]'),
            streaming: false,
            onEditImage: (u, tool) => edited = (u, tool),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Edit'));
    expect(edited, (url, ImageTool.edit));
  });

  test('an edit is sent with the message: image, painted area, size', () async {
    Map<String, dynamic>? body;
    final api = GaradApi(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('event: stop\ndata: [DONE]\n\n', 200);
      }),
    );
    await api
        .sendMessage(
          7,
          'Make the background blue',
          edit: ImageEdit(
            imageUrl: 'https://garad.ai/uploads/banner.png',
            mask: Uint8List.fromList([1, 2, 3]),
            size: '1024x1536',
          ),
        )
        .drain<void>();

    expect(body?['edit_image_url'], 'https://garad.ai/uploads/banner.png');
    expect(body?['edit_mask'], 'data:image/png;base64,${base64Encode([1, 2, 3])}');
    expect(body?['edit_size'], '1024x1536');
    expect(body?.containsKey('edit_background'), isFalse);
  });
}
