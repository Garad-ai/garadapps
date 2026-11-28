/// The AI Toolkit's data (garad.ai's Image & Video Generator), as the website's own endpoints send it.
library;

/// An image model in the Image Generator (GET /toolkit/image-models, the website's own list).
class ImageModelInfo {
  const ImageModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.imageGenerator,
    this.falAiModel,
    this.promptField = 'description',
    this.referenceMode,
    this.locked = false,
    this.requiredPlan,
    this.available = true,
    this.beta = false,
  });

  factory ImageModelInfo.fromJson(Map<String, dynamic> json) => ImageModelInfo(
    id: '${json['id']}',
    name: _shortName(json['displayName'] as String? ?? '${json['id']}'),
    provider: json['provider'] as String? ?? '',
    imageGenerator: json['imageGenerator'] as String? ?? '',
    falAiModel: json['falAiModel'] as String?,
    promptField: json['promptField'] as String? ?? 'description',
    referenceMode: json['referenceMode'] as String?,
    locked: json['locked'] == true,
    requiredPlan: json['requiredPlan'] as String?,
    available: json['availability'] != 'unavailable',
    beta: json['availability'] == 'beta',
  );

  /// "GPT-IMAGE-1.5 The latest image model released in Dec 2025." → "GPT-IMAGE-1.5".
  static String _shortName(String name) {
    final cut = RegExp(r'\s+(The|Most|Fast)\s').firstMatch(name);
    return (cut == null ? name : name.substring(0, cut.start)).trim();
  }

  final String id;
  final String name;
  final String provider;

  /// What the website sends as image_generator (the model, "fal-ai" or "stable_diffusion").
  final String imageGenerator;
  final String? falAiModel;

  /// The extra form field the prompt also goes in for this engine.
  final String promptField;

  /// How a reference picture is sent: "image_src_array", "image_src", or null (not accepted).
  final String? referenceMode;

  final bool locked;
  final String? requiredPlan;
  final bool available;
  final bool beta;

  bool get usable => available && !locked;
  bool get takesReference => referenceMode != null;
}

/// An image made with the Image Generator (GET /toolkit/images, or a generate result).
class ToolkitImage {
  const ToolkitImage({
    required this.slug,
    required this.url,
    this.id,
    this.prompt = '',
    this.model = '',
    this.pending = false,
    this.createdAt,
  });

  factory ToolkitImage.fromJson(Map<String, dynamic> json) => ToolkitImage(
    id: (json['id'] as num?)?.toInt(),
    slug: '${json['slug'] ?? json['nameOfImage'] ?? ''}',
    url: '${json['url'] ?? json['output'] ?? ''}',
    prompt: json['prompt'] as String? ?? json['input'] as String? ?? '',
    model: json['model'] as String? ?? '',
    pending: json['pending'] == true || json['status'] == 'IN_QUEUE',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? json['created_at'] as String? ?? '')?.toLocal(),
  );

  final int? id;
  final String slug;
  final String url;
  final String prompt;
  final String model;
  final bool pending;
  final DateTime? createdAt;
}

/// The Image Generator's options, with the website's values (frontend/src/ImageGenerator.tsx).
abstract final class ImageOptions {
  static const styles = [
    '3d_render', 'anime', 'cartoon', 'cyberpunk', 'impressionism', 'line', 'minimalism', 'pixel', 'realistic', //
    'watercolor',
  ];
  static const lightings = ['ambient', 'cinematic', 'dramatic', 'golden_hour', 'natural', 'neon', 'studio'];
  static const moods = ['bright', 'calm', 'cheerful', 'colorful', 'dark', 'neutral'];

  /// "golden_hour" → "Golden hour".
  static String label(String value) {
    final words = value.replaceAll(RegExp(r'[_-]'), ' ');
    if (value == '3d_render') return '3D render';
    return words[0].toUpperCase() + words.substring(1);
  }

  /// The prompt as the website sends it: the user's words, then "Art style: …. Lighting: …. Mood: …."
  static String prompt(String text, {String style = '', String lighting = '', String mood = ''}) => [
    text.trim(),
    if (style.isNotEmpty) 'Art style: ${style.replaceAll(RegExp(r'[_-]'), ' ')}.',
    if (lighting.isNotEmpty) 'Lighting: ${lighting.replaceAll('_', ' ')}.',
    if (mood.isNotEmpty) 'Mood: ${mood.replaceAll('_', ' ')}.',
  ].join(' ');
}
