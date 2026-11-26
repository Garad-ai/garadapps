/// Billing data from the website (the same plans and EVC Plus checkout as garad.ai).
library;

/// A plan as the website shows it (AIChatPro PlansController::mapPlan).
class GaradPlan {
  const GaradPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.description,
    required this.features,
    this.popular = false,
    this.team = false,
    this.contactSales = false,
    this.credits,
    this.topModels = const [],
    this.tools = const [],
    this.agents = const [],
  });

  factory GaradPlan.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? list) => [
      for (final s in (list as List? ?? const []))
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];
    return GaradPlan(
      id: '${json['id']}',
      name: json['name'] as String? ?? '',
      monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      features: strings(json['features']),
      popular: json['popular'] == true,
      // The website also treats a plan with the id "business" as a team plan.
      team: json['team'] == true || '${json['id']}' == 'business',
      contactSales: json['contactSales'] == true,
      credits: (json['credits'] as num?)?.toInt(),
      topModels: [
        for (final m in (json['flagships'] as List? ?? const []))
          if (m is Map<String, dynamic>) PlanModel.fromJson(m),
      ],
      tools: [
        for (final t in (json['tools'] as List? ?? const []))
          if (t is Map<String, dynamic>) PlanTool.fromJson(t),
      ],
      agents: strings(json['agents']),
    );
  }

  final String id;
  final String name;
  final double monthlyPrice;
  final String description;
  final List<String> features;
  final bool popular;

  /// A team plan: paid per person, at least 2 (the website's rule).
  final bool team;

  /// Enterprise: no checkout, the website handles it ("Contact sales").
  final bool contactSales;

  /// Tokens a month for images and videos (per user on team plans).
  final int? credits;

  /// The website's "Top models": its flagship chat models, with a relative cost.
  final List<PlanModel> topModels;

  /// The website's "AI Toolkit": images, videos, audio… each included or not.
  final List<PlanTool> tools;

  final List<String> agents;

  bool get free => monthlyPrice == 0;

  /// "$5", "$4.50" (like the website) or "$4.99".
  static String price(double amount) =>
      amount == amount.roundToDouble() ? '\$${amount.toStringAsFixed(0)}' : '\$${amount.toStringAsFixed(2)}';
}

/// A top model on a plan: "Claude Opus 5.5", cost 10 (×). [credits] is set for image/video models.
class PlanModel {
  const PlanModel({required this.provider, required this.name, this.cost = 1, this.credits});

  factory PlanModel.fromJson(Map<String, dynamic> json) => PlanModel(
    provider: json['provider'] as String? ?? '',
    name: json['name'] as String? ?? '',
    cost: (json['cost'] as num?)?.toDouble() ?? 1,
    credits: (json['credits'] as num?)?.toInt(),
  );

  final String provider;
  final String name;
  final double cost;
  final int? credits;
}

/// A tool in the plan's AI Toolkit: "AI Images", included, "Credits".
class PlanTool {
  const PlanTool({required this.label, required this.included, this.detail = ''});

  factory PlanTool.fromJson(Map<String, dynamic> json) => PlanTool(
    label: json['label'] as String? ?? '',
    included: json['included'] == true,
    detail: json['detail'] as String? ?? '',
  );

  final String label;
  final bool included;
  final String detail;
}

/// The user's own plan and credits (GET /billing).
class BillingStatus {
  const BillingStatus({
    this.planId,
    this.planName,
    this.monthlyPrice,
    this.status,
    this.endsAt,
    this.paidWith,
    this.credits,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>?;
    return BillingStatus(
      planId: plan == null ? null : '${plan['id']}',
      planName: plan?['name'] as String?,
      monthlyPrice: (plan?['monthlyPrice'] as num?)?.toDouble(),
      status: json['status'] as String?,
      endsAt: DateTime.tryParse(json['endsAt'] as String? ?? '')?.toLocal(),
      paidWith: json['paidWith'] as String?,
      credits: (json['credits'] as num?)?.toDouble(),
    );
  }

  final String? planId;
  final String? planName;
  final double? monthlyPrice;
  final String? status;
  final DateTime? endsAt;
  final String? paidWith;
  final double? credits;

  bool get hasPlan => planId != null;
}

/// A way to pay (today: EVC Plus, from the Hormuud wallet with the phone number).
class PaymentMethod {
  const PaymentMethod({required this.id, required this.name, required this.requiresPhone, this.description = ''});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    requiresPhone: json['requiresPhone'] == true,
    description: json['description'] as String? ?? '',
  );

  final String id;
  final String name;
  final bool requiresPhone;
  final String description;
}

/// "61 234 5678", "0612345678", "+252 61 234 5678" → "252612345678" (what EVC Plus expects).
String evcPhone(String typed) {
  var digits = typed.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('252')) return digits;
  if (digits.startsWith('0')) digits = digits.substring(1);
  return '252$digits';
}
