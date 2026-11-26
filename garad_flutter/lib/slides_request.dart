import 'api/models.dart';

/// A request for a deck, misspellings included ("make as sildes", "make presantion", "power point").
/// The server's tool rules (AiChatProService::withCorrectedFileWords) read the same words.
final _slidesWords = RegExp(
  r'\b(?:slides?|slide\s+deck|deck|presentations?|powerpoint|power\s+point|pptx?'
  r'|presantion|presantation|presentaion|presentasion|presention|presentaton|presetation|presntation'
  r'|prezentation|presentatoin|presenation|presentatin|presantetion|presenttion|presentetion'
  r'|presintation|presentition|prsentation|power\s+piont|powerpiont|powepoint|powerpont|pwerpoint'
  r'|sildes|silde|slids|slaids|slaid|sledes|slieds|sliedes|slidse|sldies|bandhig)\b',
  caseSensitive: false,
);

/// The message as the server should read it: misspelled file words written correctly ("presantion" →
/// "presentation", "power point" → "powerpoint", "sildes" → "slides"). Until garad.ai's own correction
/// (AiChatProService::withCorrectedFileWords, PR #194) is live, the server only knows the right spelling
/// and answered "I can't create slide files" with an outline. The user's bubble keeps what they typed.
String withCorrectedFileWords(String text) => text
    .replaceAllMapped(
      RegExp(
        r'\b(?:presantion|presantation|presentaion|presentasion|presention|presentaton|presetation|presntation'
        r'|prezentation|presentatoin|presenation|presentatin|presantetion|presenttion|presentetion|presintation'
        r'|presentition|prsentation|presentatio)(s?)\b',
        caseSensitive: false,
      ),
      (m) => 'presentation${m.group(1)}',
    )
    .replaceAll(
      RegExp(
        r'\b(?:power\s+point|power\s+piont|powerpiont|powepoint|powerpont|pwerpoint|powerpoit|powr\s*point)\b',
        caseSensitive: false,
      ),
      'PowerPoint',
    )
    .replaceAll(
      RegExp(r'\b(?:sildes|silde|slids|slaids|slaid|sledes|slieds|sliedes|slidse|sldies)\b', caseSensitive: false),
      'slides',
    );

/// "Make …", "create …", "samee …", "… as slides", "into a deck".
final _makeWords = RegExp(
  r'\b(?:make|create|build|generate|prepare|design|do|turn|convert|as|into|samee|sameey|samey|diyaari|ka\s+dhig)\b',
  caseSensitive: false,
);

/// Slides are asked for: a slides word, with a "make" word or in a short message ("slides please").
/// "The presentation of the results was clear" is not a request.
bool asksForSlides(String text) {
  if (!_slidesWords.hasMatch(text)) return false;
  final words = text.trim().split(RegExp(r'\s+')).length;
  return words <= 4 || _makeWords.hasMatch(text);
}

/// Decks are built by Claude's document engine, which runs only on Claude models: with DeepSeek, GPT
/// or Gemini selected, "make slides" answered "I couldn't create the requested presentation" (26 Nov).
/// For such a message, the Claude model to send it with: the cheapest one the plan opens (Haiku 5.5
/// first, then Sonnet, then any other usable Claude). Null when the chosen model is already Claude, the
/// message is not about slides, or the plan has no usable Claude model.
String? claudeModelForSlides(String text, List<ChatModelInfo> models, String? selectedId) {
  if (!asksForSlides(text)) return null;
  final selected = models.where((m) => m.id == selectedId).firstOrNull;
  if (selected != null && selected.provider.toLowerCase() == 'anthropic') return null;
  final claude = models.where((m) => m.usable && m.provider.toLowerCase() == 'anthropic').toList();
  int rank(ChatModelInfo m) => m.id.contains('haiku') ? 0 : (m.id.contains('sonnet') ? 1 : 2);
  claude.sort((a, b) => rank(a).compareTo(rank(b)));
  return claude.firstOrNull?.id;
}
