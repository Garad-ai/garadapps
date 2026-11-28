import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/screens/slides_screen.dart';
import 'package:garad_ai/local_pages.dart';

/// Presentations open as slides: the viewer is bundled with the app and served only to the app's
/// own web view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only the viewer\'s own files are served', () {
    expect(LocalPages.assetFor('/slides/index.html'), 'assets/slides/index.html');
    expect(LocalPages.assetFor('/slides/assets/index-abc.js'), 'assets/slides/assets/index-abc.js');
    expect(LocalPages.assetFor('/live/index.html'), 'assets/live/index.html');

    for (final path in [
      '/',
      '/index.html', // outside the pages' folders
      '/images/wordmark.png',
      '/fonts/SourceSerif4-OFL.txt',
      '/live/../images/wordmark.png',
      '/../images/wordmark.png',
      '/assets/../../fonts/SourceSerif4-OFL.txt',
      '/%2e%2e/images/wordmark.png',
      '/assets//x.js',
      '/./index.html',
      r'/..\images\wordmark.png',
      '/%E0%A4%A', // not valid percent-encoding
    ]) {
      expect(LocalPages.assetFor(path), isNull, reason: path);
    }
  });

  test('file names read as titles', () {
    expect(slidesTitle('Online_Business_Presentation.pptx'), 'Online Business Presentation');
    expect(slidesTitle('online-business-idea'), 'online-business-idea');
    expect(slidesTitle('  Market Plan.PPTX '), 'Market Plan');
    expect(slidesTitle(null), '');
  });

  test('WebAssembly, scripts and styles get the right types', () {
    expect(LocalPages.contentTypeFor('assets/pptx_wasm_bg-1.wasm').mimeType, 'application/wasm');
    expect(LocalPages.contentTypeFor('assets/index-1.js').mimeType, 'text/javascript');
    expect(LocalPages.contentTypeFor('assets/index-1.css').mimeType, 'text/css');
    expect(LocalPages.contentTypeFor('index.html').mimeType, ContentType.html.mimeType);
  });

  test('the built viewer is in the app, with everything its page loads', () async {
    final page = await rootBundle.loadString('assets/slides/index.html');
    final files = RegExp(r'(?:src|href)="\./([^"]+)"').allMatches(page).map((m) => m.group(1)!).toList();
    expect(files, isNotEmpty, reason: 'run `npm run build` in slides_viewer/');
    for (final file in files) {
      expect((await rootBundle.load('assets/slides/$file')).lengthInBytes, greaterThan(0), reason: file);
    }
  });

  test('the built live video page is in the app, with everything it loads', () async {
    final page = await rootBundle.loadString('assets/live/index.html');
    final files = RegExp(r'(?:src|href)="\./([^"]+)"').allMatches(page).map((m) => m.group(1)!).toList();
    expect(files, isNotEmpty, reason: 'run `npm run build` in live_client/');
    for (final file in files) {
      expect((await rootBundle.load('assets/live/$file')).lengthInBytes, greaterThan(0), reason: file);
    }
    // The microphone worklet is a file of its own (audio worklets refuse data: URLs).
    final script = files.firstWhere((f) => f.endsWith('.js'));
    final code = await rootBundle.loadString('assets/live/$script');
    final worklet = RegExp(r'capture-worklet-[\w-]+\.js').firstMatch(code)?.group(0);
    expect(worklet, isNotNull);
    expect((await rootBundle.load('assets/live/assets/$worklet')).lengthInBytes, greaterThan(0));
  });
}
