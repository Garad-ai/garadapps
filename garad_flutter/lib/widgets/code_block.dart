import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import '../app_messages.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// A code block in an answer, ChatGPT-style: a card with the language, Copy, and ▶ Run for Python
/// and JavaScript. Run executes the code on the phone itself (Python through Pyodide, in a hidden web
/// view) and shows its output under the code — printed text, errors, and charts (matplotlib).
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.language, required this.code, this.done = true, this.setup = const []});

  /// The fence's language tag as written (```python → "python"); may be empty.
  final String language;
  final String code;

  /// Python: the earlier parts of the same example, run silently first so this part can use what
  /// they defined (see [splitCodeSections]).
  final List<String> setup;

  /// False while the AI is still writing it (no Run yet).
  final bool done;

  /// Builds the hidden web view that runs [page]; replaceable in tests.
  @visibleForTesting
  static Widget Function(String page, void Function(String message) onMessage) runnerBuilder = _runner;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

/// A long example divided by section comments (`# ===== 1. Variables =====`, `// --- Loops ---`) →
/// its sections, each with its title (null for code before the first one, such as imports). Fewer
/// than two such comments: the whole code as one section.
List<({String? title, String code})> splitCodeSections(String code) {
  final marker = RegExp(r'^[ \t]*(?:#|//)[ \t]*[=#*~-]{3,}[ \t]*(.+?)[ \t]*[=#*~-]{3,}[ \t]*$', multiLine: true);
  final found = marker.allMatches(code).toList();
  if (found.length < 2) return [(title: null, code: code)];
  final sections = <({String? title, String code})>[];
  final before = code.substring(0, found.first.start).trim();
  if (before.isNotEmpty) sections.add((title: null, code: before));
  for (final (i, m) in found.indexed) {
    final end = i + 1 < found.length ? found[i + 1].start : code.length;
    final body = code.substring(m.end, end).trim();
    if (body.isNotEmpty) sections.add((title: m.group(1)!.trim(), code: body));
  }
  return sections;
}

/// What a language tag means: its label, how to highlight it, whether it can run here.
({String label, String? highlight, String? runner, bool prose}) codeLanguage(String tag) {
  final t = tag.trim().toLowerCase();
  return switch (t) {
    'python' || 'py' || 'python3' => (label: 'Python', highlight: 'python', runner: 'python', prose: false),
    'javascript' || 'js' || 'node' || 'mjs' => (
      label: 'JavaScript',
      highlight: 'javascript',
      runner: 'javascript',
      prose: false,
    ),
    'typescript' || 'ts' => (label: 'TypeScript', highlight: 'typescript', runner: null, prose: false),
    'jsx' || 'tsx' => (label: t.toUpperCase(), highlight: 'javascript', runner: null, prose: false),
    'bash' || 'sh' || 'shell' || 'zsh' || 'console' => (label: 'Bash', highlight: 'bash', runner: null, prose: false),
    'powershell' || 'ps1' => (label: 'PowerShell', highlight: 'powershell', runner: null, prose: false),
    'html' || 'xml' => (label: t.toUpperCase(), highlight: 'xml', runner: null, prose: false),
    'css' || 'scss' || 'sql' || 'json' || 'yaml' || 'php' => (
      label: t.toUpperCase(),
      highlight: t,
      runner: null,
      prose: false,
    ),
    'c' || 'cpp' || 'c++' => (label: t == 'c' ? 'C' : 'C++', highlight: 'cpp', runner: null, prose: false),
    'csharp' || 'cs' || 'c#' => (label: 'C#', highlight: 'cs', runner: null, prose: false),
    'dart' || 'java' || 'kotlin' || 'swift' || 'go' || 'rust' || 'ruby' => (
      label: t[0].toUpperCase() + t.substring(1),
      highlight: t,
      runner: null,
      prose: false,
    ),
    // Ready-to-send drafts (AiChatProService: email, letter, speech, script, post, writing).
    'email' || 'letter' || 'speech' || 'script' || 'post' || 'writing' => (
      label: t[0].toUpperCase() + t.substring(1),
      highlight: null,
      runner: null,
      prose: true,
    ),
    '' || 'text' || 'txt' || 'plaintext' || 'output' => (label: 'Plain text', highlight: null, runner: null, prose: false),
    _ => (label: t[0].toUpperCase() + t.substring(1), highlight: t, runner: null, prose: false),
  };
}

/// One line of a run's output.
class _Line {
  const _Line(this.text, {this.error = false, this.image});
  final String text;
  final bool error;
  final Uint8List? image;
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  bool _running = false;
  int _runs = 0;
  String? _page;
  final List<_Line> _output = [];
  Timer? _limit;
  void Function()? _stopListening;
  late String _runId;

  @override
  void dispose() {
    _limit?.cancel();
    _stopListening?.call();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _run() {
    final runner = codeLanguage(widget.language).runner;
    if (runner == null || _running) return;
    _runId = '${DateTime.now().microsecondsSinceEpoch}';
    _stopListening?.call();
    _stopListening = listenForWebMessages('garadRun', _onMessage);
    _limit?.cancel();
    // The first Python run downloads Python itself (about 10 MB); later runs are quick.
    _limit = Timer(const Duration(minutes: 2), () => _finish(chatStrings.runTookTooLong));
    setState(() {
      _running = true;
      _runs++;
      _output.clear();
      _page = codeRunPage(runner, widget.code, _runId, setup: widget.setup);
    });
  }

  void _onMessage(String raw) {
    if (!mounted || !_running) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['id'] != _runId) return; // another code block's run
    final text = '${m['text'] ?? ''}';
    switch (m['kind']) {
      case 'out':
        setState(() => _output.add(_Line(text)));
      case 'err':
        setState(() => _output.add(_Line(cleanTraceback(text), error: true)));
      case 'img':
        try {
          final bytes = base64Decode(text);
          setState(() => _output.add(_Line('', image: bytes)));
        } catch (_) {}
      case 'done':
        _finish(null);
    }
  }

  void _finish(String? error) {
    _limit?.cancel();
    _stopListening?.call();
    _stopListening = null;
    if (!mounted) return;
    setState(() {
      if (error != null) _output.add(_Line(error, error: true));
      _running = false;
      _page = null; // the hidden web view goes away
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final lang = codeLanguage(widget.language);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono', 'Courier New'],
      fontSize: 13.5,
      height: 1.5,
      color: c.text,
    );
    final body = lang.prose
        ? SelectableText(widget.code, style: TextStyle(fontSize: 15.5, height: 1.5, color: c.text))
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(TextSpan(style: mono, children: highlightCode(widget.code, lang.highlight, dark))),
          );

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // </> Python ……………… ⧉ Copy · ▶ Run
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Icon(lang.prose ? Icons.notes : Icons.code, size: 16, color: c.muted),
                const SizedBox(width: 6),
                Text(lang.label, style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                IconButton(
                  tooltip: _copied ? chatStrings.codeCopied : chatStrings.copyCode,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(_copied ? Icons.check : Icons.copy_rounded, size: 17, color: c.muted),
                  onPressed: _copy,
                ),
                if (lang.runner != null && widget.done)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: OutlinedButton.icon(
                      onPressed: _running ? null : _run,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: BorderSide(color: c.line),
                        foregroundColor: c.text,
                        shape: const StadiumBorder(),
                      ),
                      icon: _running
                          ? SizedBox.square(
                              dimension: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.muted),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(_running ? chatStrings.running : chatStrings.run, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: body),
        ],
      ),
    );

    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        if (_runs > 0) _OutputView(lines: _output, running: _running, mono: mono),
        // The hidden runner: tiny, invisible, gone when the run ends.
        if (page != null)
          SizedBox(
            width: 2,
            height: 2,
            child: Opacity(
              opacity: 0,
              child: KeyedSubtree(key: ValueKey(_runId), child: CodeBlock.runnerBuilder(page, _onMessage)),
            ),
          ),
      ],
    );
  }
}

class _OutputView extends StatelessWidget {
  const _OutputView({required this.lines, required this.running, required this.mono});

  final List<_Line> lines;
  final bool running;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final text = lines.where((l) => l.image == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(chatStrings.output, style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surfaceStrong,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                SelectableText.rich(
                  TextSpan(
                    style: mono,
                    children: [
                      for (final (i, l) in text.indexed)
                        TextSpan(text: i == 0 ? l.text : '\n${l.text}', style: l.error ? TextStyle(color: c.danger) : null),
                    ],
                  ),
                ),
              for (final l in lines)
                if (l.image != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(l.image!)),
                  ),
              if (running)
                Text(chatStrings.runningCode, style: mono.copyWith(color: c.muted))
              else if (lines.isEmpty)
                Text(chatStrings.noOutput, style: mono.copyWith(color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Python's error without Pyodide's own internal lines: what a learner needs to read.
@visibleForTesting
String cleanTraceback(String text) {
  final lines = text.split('\n');
  final kept = <String>[];
  var skip = false;
  for (final line in lines) {
    if (line.startsWith('  File "/lib/python') || line.contains('_pyodide')) {
      skip = true; // this frame's location line, and its code line below
      continue;
    }
    if (skip && line.startsWith('    ')) {
      skip = false;
      continue;
    }
    skip = false;
    kept.add(line);
  }
  return kept.join('\n').trim();
}

// ---- Syntax colors ----

const _lightColors = {
  'keyword': Color(0xFF9333EA),
  'built_in': Color(0xFF0E7490),
  'type': Color(0xFF0E7490),
  'literal': Color(0xFFB45309),
  'number': Color(0xFFB45309),
  'string': Color(0xFF15803D),
  'comment': Color(0xFF8A8F98),
  'function': Color(0xFF2563EB),
  'title': Color(0xFF2563EB),
  'params': Color(0xFF374151),
  'meta': Color(0xFF6B7280),
  'attr': Color(0xFFB45309),
  'attribute': Color(0xFFB45309),
  'tag': Color(0xFF9333EA),
  'name': Color(0xFF9333EA),
  'variable': Color(0xFFDC2626),
  'symbol': Color(0xFFB45309),
};

const _darkColors = {
  'keyword': Color(0xFFC792EA),
  'built_in': Color(0xFF7DD3FC),
  'type': Color(0xFF7DD3FC),
  'literal': Color(0xFFF78C6C),
  'number': Color(0xFFF78C6C),
  'string': Color(0xFFC3E88D),
  'comment': Color(0xFF7F8794),
  'function': Color(0xFF82AAFF),
  'title': Color(0xFF82AAFF),
  'params': Color(0xFFD4D4D8),
  'meta': Color(0xFF9CA3AF),
  'attr': Color(0xFFFFCB6B),
  'attribute': Color(0xFFFFCB6B),
  'tag': Color(0xFFF07178),
  'name': Color(0xFFF07178),
  'variable': Color(0xFFF07178),
  'symbol': Color(0xFFF78C6C),
};

/// [code] as colored spans ([language] as highlight.js names it); plain text when unknown.
List<TextSpan> highlightCode(String code, String? language, bool dark) {
  if (language == null) return [TextSpan(text: code)];
  final List<Node>? nodes;
  try {
    nodes = highlight.parse(code, language: language).nodes;
  } catch (_) {
    return [TextSpan(text: code)];
  }
  if (nodes == null) return [TextSpan(text: code)];
  final colors = dark ? _darkColors : _lightColors;
  TextSpan span(Node node) {
    final color = colors[node.className?.split(' ').first.replaceAll('hljs-', '')];
    final style = color == null ? null : TextStyle(color: color);
    if (node.value != null) return TextSpan(text: node.value, style: style);
    return TextSpan(style: style, children: [for (final child in node.children ?? const <Node>[]) span(child)]);
  }

  return [for (final node in nodes) span(node)];
}

// ---- Running code ----

const _pyodide = 'https://cdn.jsdelivr.net/pyodide/v0.26.4/full/';

/// A page that runs [code] and reports `{id, kind: out|err|img|done, text}` as JSON: on phones
/// through the web view's `garadRun` handler, in browsers by posting `{garadRun: …}` to this page.
String codeRunPage(String runner, String code, String runId, {List<String> setup = const []}) {
  // As a JSON string inside <script>; "<" escaped so "</script>" in the code can't end the script.
  final lt = '${String.fromCharCode(92)}x3c';
  final embedded = jsonEncode(code).replaceAll('<', lt);
  final embeddedSetup = jsonEncode(setup).replaceAll('<', lt);
  final id = jsonEncode(runId);
  const send = '''
function send(kind, text) {
  var m = JSON.stringify({ id: RUN_ID, kind: kind, text: String(text) });
  var b = window.flutter_inappwebview;
  if (b && b.callHandler) { b.callHandler("garadRun", m); return; }
  try { window.parent.postMessage({ garadRun: m }, "*"); } catch (e) {}
}''';
  if (runner == 'javascript') {
    return '''<!doctype html><html><head><meta charset="utf-8"></head><body><script>
var RUN_ID = $id;
$send
function fmt(v) { if (typeof v === "string") return v; try { return JSON.stringify(v, null, 2); } catch (e) { return String(v); } }
console.log = console.info = console.debug = function () { send("out", Array.prototype.map.call(arguments, fmt).join(" ")); };
console.warn = console.error = function () { send("err", Array.prototype.map.call(arguments, fmt).join(" ")); };
(async function () {
  try {
    var AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    await new AsyncFunction($embedded)();
    send("done", "");
  } catch (e) { send("err", (e && e.name ? e.name + ": " : "") + (e && e.message ? e.message : String(e))); send("done", "error"); }
})();
</script></body></html>''';
  }
  return '''<!doctype html><html><head><meta charset="utf-8"></head><body><script>
var RUN_ID = $id;
$send
</script>
<script src="${_pyodide}pyodide.js"></script>
<script>
(async function () {
  try {
    var code = $embedded;
    var setup = $embeddedSetup;
    var quiet = false;
    var py = await loadPyodide({ indexURL: "$_pyodide",
      stdout: function (t) { if (!quiet) send("out", t); }, stderr: function (t) { if (!quiet) send("err", t); } });
    await py.loadPackagesFromImports(setup.join("\\n") + "\\n" + code, { messageCallback: function () {}, errorCallback: function () {} });
    // Charts are drawn off screen and sent as pictures; input() has no keyboard here: it gets "".
    await py.runPythonAsync([
      "import sys, builtins",
      "try:",
      "    import matplotlib; matplotlib.use('AGG')",
      "except Exception:",
      "    pass",
      "def _garad_input(prompt=''):",
      "    print(prompt)",
      "    return ''",
      "builtins.input = _garad_input",
    ].join("\\n"));
    // The example's earlier parts, silently (an error in one, such as a deliberate 1/0, is skipped).
    quiet = true;
    for (var s = 0; s < setup.length; s++) { try { await py.runPythonAsync(setup[s]); } catch (e) {} }
    if (setup.length) await py.runPythonAsync("if 'matplotlib.pyplot' in sys.modules:\\n    sys.modules['matplotlib.pyplot'].close('all')");
    quiet = false;
    await py.runPythonAsync(code);
    var pictures = await py.runPythonAsync([
      "_garad_out = []",
      "if 'matplotlib.pyplot' in sys.modules:",
      "    import io, base64",
      "    import matplotlib.pyplot as _garad_plt",
      "    for _n in _garad_plt.get_fignums():",
      "        _b = io.BytesIO()",
      "        _garad_plt.figure(_n).savefig(_b, format='png', bbox_inches='tight', dpi=110)",
      "        _garad_out.append(base64.b64encode(_b.getvalue()).decode())",
      "    _garad_plt.close('all')",
      "_garad_out",
    ].join("\\n"));
    var list = pictures.toJs();
    for (var i = 0; i < list.length; i++) send("img", list[i]);
    send("done", "");
  } catch (e) { send("err", e && e.message ? e.message : String(e)); send("done", "error"); }
})();
</script></body></html>''';
}

Widget _runner(String page, void Function(String message) onMessage) => InAppWebView(
  initialData: InAppWebViewInitialData(data: page, baseUrl: WebUri('https://run.garad.local/')),
  initialSettings: InAppWebViewSettings(
    javaScriptEnabled: true,
    allowFileAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    transparentBackground: true,
    iframeSandbox: {Sandbox.ALLOW_SCRIPTS},
  ),
  onWebViewCreated: (controller) {
    if (kIsWeb) return; // browsers: messages are posted to the page (listenForWebMessages)
    controller.addJavaScriptHandler(
      handlerName: 'garadRun',
      callback: (args) => onMessage(args.isEmpty ? '' : '${args.first}'),
    );
  },
);
