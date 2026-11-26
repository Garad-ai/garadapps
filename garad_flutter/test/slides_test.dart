import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/screens/slides_screen.dart';
import 'package:garad_ai/slides_server.dart';

/// Presentations open as slides: the viewer is bundled with the app and served only to the app's
/// own web view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only the viewer\'s own files are served', () {
    expect(SlidesServer.assetFor('/index.html'), 'assets/slides/index.html');
    expect(SlidesServer.assetFor('/assets/index-abc.js'), 'assets/slides/assets/index-abc.js');

    for (final path in [
      '/',
      '/../images/wordmark.png',
      '/assets/../../fonts/SourceSerif4-OFL.txt',
      '/%2e%2e/images/wordmark.png',
      '/assets//x.js',
      '/./index.html',
      r'/..\images\wordmark.png',
      '/%E0%A4%A', // not valid percent-encoding
    ]) {
      expect(SlidesServer.assetFor(path), isNull, reason: path);
    }
  });

  test('file names read as titles', () {
    expect(slidesTitle('Online_Business_Presentation.pptx'), 'Online Business Presentation');
    expect(slidesTitle('online-business-idea'), 'online-business-idea');
    expect(slidesTitle('  Market Plan.PPTX '), 'Market Plan');
    expect(slidesTitle(null), '');
  });

  test('WebAssembly, scripts and styles get the right types', () {
    expect(SlidesServer.contentTypeFor('assets/pptx_wasm_bg-1.wasm').mimeType, 'application/wasm');
    expect(SlidesServer.contentTypeFor('assets/index-1.js').mimeType, 'text/javascript');
    expect(SlidesServer.contentTypeFor('assets/index-1.css').mimeType, 'text/css');
    expect(SlidesServer.contentTypeFor('index.html').mimeType, ContentType.html.mimeType);
  });

  test('the built viewer is in the app, with everything its page loads', () async {
    final page = await rootBundle.loadString('assets/slides/index.html');
    final files = RegExp(r'(?:src|href)="\./([^"]+)"').allMatches(page).map((m) => m.group(1)!).toList();
    expect(files, isNotEmpty, reason: 'run `npm run build` in slides_viewer/');
    for (final file in files) {
      expect((await rootBundle.load('assets/slides/$file')).lengthInBytes, greaterThan(0), reason: file);
    }
  });
}
