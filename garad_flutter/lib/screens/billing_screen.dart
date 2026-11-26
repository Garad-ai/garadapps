import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/billing.dart';
import '../api/garad_api.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';

String _t(String so, String en) => chatStrings.isSomali ? so : en;

/// Billing, ChatGPT-style: ✕, "Upgrade your plan", a pill switcher of the website's plans
/// (Basic, Standard, Professional, Business…), one plan at a time (big price, features with icons)
/// and one purple button at the bottom. Paying is the website's EVC Plus (the phone approves).
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<GaradPlan>? _plans;
  List<PaymentMethod> _methods = const [];
  BillingStatus? _status;
  String? _error;

  /// The plan on screen. Starts on the popular plan the user doesn't have yet.
  int? _index;
  PageController? _pages;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// Their plan's id; with no subscription, the free plan (the website's "Current" on Basic).
  String? _currentId(List<GaradPlan> plans) =>
      _status?.planId ?? plans.where((p) => p.free).map((p) => p.id).firstOrNull;

  Future<void> _load() async {
    final api = context.read<AuthState>().api;
    setState(() => _error = null);
    try {
      final results = await Future.wait([api.plans(), api.paymentMethods(), api.billing()]);
      if (!mounted) return;
      final plans = results[0] as List<GaradPlan>;
      setState(() {
        _plans = plans;
        _methods = results[1] as List<PaymentMethod>;
        _status = results[2] as BillingStatus;
        if (_index == null && plans.isNotEmpty) {
          final current = _currentId(plans);
          final start = plans.indexWhere((p) => p.popular && p.id != current);
          _index = start >= 0 ? start : 0;
          _pages = PageController(initialPage: _index!);
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _show(int i) {
    setState(() => _index = i);
    _pages?.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Future<void> _choose(GaradPlan plan) async {
    if (plan.contactSales) {
      // Enterprise is handled on the website's plans page.
      await launchUrl(
        Uri.parse(apiBaseUrl.replaceFirst(RegExp(r'/api/mobile$'), '/plans')),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final method = _methods.isEmpty ? null : _methods.first;
    final messenger = ScaffoldMessenger.of(context);
    if (method == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(_t('Lacag bixintu hadda ma shaqaynayso.', "Payments aren't available right now."))),
      );
      return;
    }
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PaySheet(plan: plan, method: method),
    );
    if (message == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  /// "Your plan: Free" or "Your plan: Standard · 30 credits left · until 25/12/2026".
  String _statusLine() {
    final s = _status;
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return [
      _t('Qorshahaaga: ', 'Your plan: ') + (s?.planName ?? _t('Bilaash', 'Free')),
      if (s?.credits case final credits?)
        _t('${credits.toStringAsFixed(0)} kredit ka haray', '${credits.toStringAsFixed(0)} credits left'),
      if (s?.endsAt case final ends?) _t('ilaa ${date(ends)}', 'until ${date(ends)}'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final plans = _plans;
    final index = _index;

    final Widget body;
    if (_error != null) {
      body = _ErrorCard(message: _error!, onRetry: _load);
    } else if (plans == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (plans.isEmpty || index == null) {
      body = Center(
        child: Text(_t('Hadda qorshe ma jiro.', 'No plans right now.'), style: TextStyle(color: c.muted)),
      );
    } else {
      final plan = plans[index];
      final currentId = _currentId(plans);
      final current = plan.id == currentId;
      body = Column(
        children: [
          Text(
            _t('Kor u qaad qorshahaaga', 'Upgrade your plan'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _statusLine(),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlanTabs(plans: plans, index: index, onTap: _show),
          ),
          const SizedBox(height: 4),
          // Clipped, so the plan's list never slides up under the switcher when scrolled.
          Expanded(
            child: ClipRect(
              child: PageView.builder(
                controller: _pages,
                itemCount: plans.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _PlanPage(plan: plans[i], current: plans[i].id == currentId),
              ),
            ),
          ),
          // The free plan has nothing to buy: no button unless it's theirs.
          if (current || !plan.free)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: current ? null : () => _choose(plan),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: c.brandSoft,
                    disabledForegroundColor: c.brand,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    current
                        ? _t('Qorshahaaga hadda', 'Your current plan')
                        : plan.contactSales
                        ? _t('La xiriir iibka', 'Contact sales')
                        : _t('Qaado ${plan.name}', 'Get ${plan.name}'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 16),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  color: c.text,
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The pill switcher: one segment per plan, the one on screen filled.
class _PlanTabs extends StatelessWidget {
  const _PlanTabs({required this.plans, required this.index, required this.onTap});

  final List<GaradPlan> plans;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Four plans (Basic … Business) need a slightly smaller label to fit a phone.
    final fontSize = plans.length > 3 ? 13.0 : 14.5;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.text.withValues(alpha: 0.06), c.background),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < plans.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == index ? (dark ? c.text.withValues(alpha: 0.14) : Colors.white) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: i == index && !dark
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      plans[i].name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i == index ? c.brand : c.muted,
                        fontSize: fontSize,
                        fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One plan: name, big price, a line about it, then what's included with an icon each.
class _PlanPage extends StatelessWidget {
  const _PlanPage({required this.plan, required this.current});

  final GaradPlan plan;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                plan.name,
                style: TextStyle(color: c.text, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.4),
              ),
            ),
            const SizedBox(width: 10),
            if (current)
              _Badge(text: _t('Qorshahaaga', 'Current'))
            else if (plan.popular)
              _Badge(text: _t('Caan ah', 'Popular')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              plan.free ? _t('Bilaash', 'Free') : GaradPlan.price(plan.monthlyPrice),
              style: TextStyle(color: c.text, fontSize: 44, fontWeight: FontWeight.w600, height: 1.1),
            ),
            if (!plan.free) ...[
              const SizedBox(width: 8),
              Text(
                plan.team ? _t('USD / qofkii\nbishii', 'USD / person\n/ month') : _t('USD /\nbishii', 'USD /\nmonth'),
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.25),
              ),
            ],
          ],
        ),
        if (plan.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(plan.description, style: TextStyle(color: c.text, fontSize: 16, height: 1.4)),
        ],
        const SizedBox(height: 20),
        if (plan.credits case final credits? when credits > 0)
          _Feature(icon: Icons.bolt_outlined, text: _t('$credits kredit bishii', '$credits credits a month')),
        for (final f in plan.features) _Feature(icon: _featureIcon(f), text: f),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: c.brand),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(text, style: TextStyle(color: c.text, fontSize: 15.5, height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fitting icon for a feature line, from its words (the website sends plain text).
IconData _featureIcon(String feature) {
  final f = feature.toLowerCase();
  bool has(List<String> words) => words.any(f.contains);
  if (has(['code', 'developer', 'api'])) return Icons.code;
  if (has(['image', 'picture', 'photo', 'sawir'])) return Icons.image_outlined;
  if (has(['video', 'muuqaal'])) return Icons.videocam_outlined;
  if (has(['voice', 'audio', 'speech', 'call', 'codka'])) return Icons.mic_none;
  if (has(['document', 'pdf', 'file', 'dukumenti'])) return Icons.description_outlined;
  if (has(['team', 'member', 'seat', 'workspace', 'koox'])) return Icons.group_outlined;
  if (has(['support', 'help', 'taageero'])) return Icons.support_agent;
  if (has(['agent', 'bot'])) return Icons.smart_toy_outlined;
  if (has(['webhook'])) return Icons.webhook;
  if (has(['web search', 'research'])) return Icons.travel_explore;
  if (has(['analytics', 'report'])) return Icons.insights;
  if (has(['sso', 'login', 'role', 'security', 'access'])) return Icons.lock_outline;
  if (has(['knowledge'])) return Icons.menu_book_outlined;
  if (has(['brand', 'label'])) return Icons.palette_outlined;
  if (has(['manager'])) return Icons.person_outline;
  if (has(['uptime', 'sla'])) return Icons.verified_outlined;
  if (has(['storage', ' gb'])) return Icons.cloud_outlined;
  if (has(['memory', 'history', 'project'])) return Icons.folder_outlined;
  if (has(['chat', 'message', 'model'])) return Icons.chat_bubble_outline;
  if (has(['everything', 'all ', 'unlimited', 'priority'])) return Icons.auto_awesome_outlined;
  return Icons.check;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: c.brandSoft),
      child: Text(
        text,
        style: TextStyle(color: c.brand, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(_t('Isku day mar kale', 'Try again'))),
        ],
      ),
    );
  }
}

/// Pay for a plan with EVC Plus: the phone number, then the phone is asked to approve the payment
/// with the EVC PIN. Pops with the server's message once the plan is active.
class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.plan, required this.method});

  final GaradPlan plan;
  final PaymentMethod method;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _phone = TextEditingController();
  int _seats = 2;
  bool _paying = false;
  String? _error;

  static const _minSeats = 2;
  static const _maxSeats = 100;

  int get _count => widget.plan.team ? _seats : 1;

  double get _total => widget.plan.monthlyPrice * _count;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = _t('Geli lambarkaaga EVC Plus.', 'Enter your EVC Plus number.'));
      return;
    }
    final phone = evcPhone(_phone.text);
    // 252 + 9 digits (61…, 77…, 68…).
    if (!RegExp(r'^252\d{9}$').hasMatch(phone)) {
      setState(
        () => _error = _t(
          'Geli lambar EVC Plus oo sax ah (9 god).',
          'Enter a valid EVC Plus number (9 digits).',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final message = await context.read<AuthState>().api.checkout(
        planId: widget.plan.id,
        method: widget.method.id,
        phone: phone,
        seats: widget.plan.team ? _seats : null,
      );
      if (mounted) {
        Navigator.of(context).pop(message.isEmpty ? _t('Qorshaha waa la furay.', 'Plan activated.') : message);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _paying = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final plan = widget.plan;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t('Bixi ${plan.name}', 'Pay for ${plan.name}'),
            style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            widget.method.description.isEmpty
                ? widget.method.name
                : '${widget.method.name} · ${widget.method.description}',
            style: TextStyle(color: c.muted, fontSize: 14),
          ),
          if (plan.team) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(_t('Tirada dadka', 'People'), style: TextStyle(color: c.text, fontSize: 15)),
                ),
                IconButton(
                  onPressed: _paying || _seats <= _minSeats ? null : () => setState(() => _seats--),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_seats',
                  style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  onPressed: _paying || _seats >= _maxSeats ? null : () => setState(() => _seats++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            enabled: !_paying,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: InputDecoration(
              labelText: _t('Lambarka EVC Plus', 'EVC Plus number'),
              prefixText: '+252 ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _pay(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ],
          if (_paying) ...[
            const SizedBox(height: 12),
            Text(
              _t(
                'Eeg taleefankaaga: ku ansixi lacag bixinta PIN-ka EVC Plus.',
                'Check your phone and approve the payment with your EVC Plus PIN.',
              ),
              style: TextStyle(color: c.brand, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _paying ? null : _pay,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: c.brandSoft,
                shape: const StadiumBorder(),
              ),
              child: _paying
                  ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.brand))
                  : Text(
                      _t('Bixi ${GaradPlan.price(_total)}', 'Pay ${GaradPlan.price(_total)}'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
