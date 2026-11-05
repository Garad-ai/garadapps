import 'dart:async';

import 'package:flutter/material.dart';
import 'package:garad_agent/garad_agent.dart';

import '../strings.dart';
import '../theme.dart';

enum _Status { off, starting, on }

const _testDelay = Duration(seconds: 5);
const _maxShown = 80;
const _green = Color(0xFF2E9D5B);
const _amber = Color(0xFFD99A1E);

/// Consent and controls for the Garad agent (docs/AGENT_PLAN.md): explains what it reads and
/// the safety rules before the user is sent to Accessibility settings, shows whether it is on,
/// and has a read test for testers.
class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _recheck;
  _Status _status = _Status.off;
  bool _consent = false;
  bool _reading = false;
  ScreenReadResult? _result;
  bool _notifications = false;
  bool _announce = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    GaradAgent.getAnnounceAloud().then((value) {
      if (mounted) setState(() => _announce = value);
    });
    // The user turns the service on in system settings, so re-check whenever Garad comes back.
    // The service connects a moment after it is switched on, hence the second check.
    _lifecycle = AppLifecycleListener(onResume: () {
      _refresh();
      _recheck?.cancel();
      _recheck = Timer(const Duration(milliseconds: 1200), _refresh);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _recheck?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final connected = await GaradAgent.isConnected();
    final enabled = connected || await GaradAgent.isEnabled();
    final notifications = await GaradAgent.isNotificationAccessEnabled();
    if (!mounted) return;
    setState(() {
      _status = connected ? _Status.on : (enabled ? _Status.starting : _Status.off);
      _notifications = notifications;
    });
  }

  Future<void> _testRead() async {
    setState(() {
      _reading = true;
      _result = null;
    });
    try {
      final result = await GaradAgent.readScreen(_testDelay);
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _reading = false);
      _refresh();
    }
  }

  Future<void> _turnOff() async {
    await GaradAgent.disable();
    setState(() => _result = null);
    Timer(const Duration(milliseconds: 300), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final body = TextStyle(color: c.muted, fontSize: 15, height: 1.45);
    final cardTitle = TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700);

    Widget card(List<Widget> children) => Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line, width: 0.5),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 8), children[i]],
            ],
          ),
        );

    Widget heading(String text) => Semantics(header: true, child: Text(text, style: cardTitle));

    Widget dot(Color color) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );

    final statusLabel = switch (_status) {
      _Status.on => strings.agentStatusOn,
      _Status.starting => strings.agentStatusStarting,
      _Status.off => strings.agentStatusOff,
    };

    final children = <Widget>[
      Text(strings.agentIntro, style: TextStyle(color: c.text, fontSize: 17, height: 1.45)),
      if (!GaradAgent.isSupported)
        card([Text(strings.agentUnsupported, style: body)])
      else ...[
        card([heading(strings.agentReadsTitle), Text(strings.agentReadsBody, style: body)]),
        card([
          heading(strings.agentRulesTitle),
          for (final rule in strings.agentRules)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body.copyWith(color: c.brand, fontWeight: FontWeight.w700)),
                Expanded(child: Text(rule, style: body)),
              ],
            ),
        ]),
        Semantics(
          liveRegion: true,
          child: card([
            Row(children: [
              dot(switch (_status) { _Status.on => _green, _Status.starting => _amber, _Status.off => c.faint }),
              const SizedBox(width: 10),
              Expanded(child: Text('${strings.agentTitle}: $statusLabel', style: cardTitle)),
            ]),
          ]),
        ),
        if (_status == _Status.off) ...[
          CheckboxListTile(
            value: _consent,
            onChanged: (value) => setState(() => _consent = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: c.brand,
            title: Text(strings.agentConsent,
                style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          _PrimaryButton(
            label: strings.agentOpenSettings,
            onPressed: _consent ? GaradAgent.openSettings : null,
            color: c.brand,
          ),
          Text(strings.agentSettingsHint, style: TextStyle(color: c.muted, fontSize: 13, height: 1.45)),
        ] else ...[
          card([
            heading(strings.agentTestTitle),
            Text(strings.agentTestHint, style: body),
            _PrimaryButton(
              label: _reading ? strings.agentTestWaiting : strings.agentTestButton,
              onPressed: _reading || _status != _Status.on ? null : _testRead,
              color: c.brand,
              busy: _reading,
            ),
            if (_result != null) _ReadResultView(result: _result!),
          ]),
          _SecondaryButton(label: strings.agentTurnOff, onPressed: _turnOff, color: c.danger, border: c.line),
          _SecondaryButton(
            label: strings.agentOpenSettings,
            onPressed: GaradAgent.openSettings,
            color: c.text,
            border: c.line,
          ),
        ],
        card([
          heading(strings.agentMessagesTitle),
          Text(strings.agentMessagesBody, style: body),
          Semantics(
            liveRegion: true,
            child: Row(children: [
              dot(_notifications ? _green : c.faint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_notifications ? strings.agentMessagesOn : strings.agentMessagesOff,
                    style: body.copyWith(color: c.text)),
              ),
            ]),
          ),
          _SecondaryButton(
            label: strings.agentMessagesOpen,
            onPressed: GaradAgent.openNotificationSettings,
            color: c.text,
            border: c.line,
          ),
          if (_notifications)
            SwitchListTile(
              value: _announce,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: c.brand,
              title: Text(strings.agentAnnounce, style: body.copyWith(color: c.text)),
              onChanged: (value) {
                GaradAgent.setAnnounceAloud(value);
                setState(() => _announce = value);
              },
            ),
        ]),
      ],
    ];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        title: Text(strings.agentTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, index) => children[index],
        ),
      ),
    );
  }
}

class _ReadResultView extends StatelessWidget {
  const _ReadResultView({required this.result});

  final ScreenReadResult result;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final summary = TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600);

    if (!result.available) {
      final message = switch (result.reason) {
        'blocked_app' => strings.agentReasonBlocked,
        'no_window' => strings.agentReasonNoWindow,
        'unsupported' => strings.agentUnsupported,
        _ => strings.agentReasonOff,
      };
      return Text(message, style: summary);
    }

    final shown = result.elements
        .where((e) => (e.text ?? '').isNotEmpty || (e.description ?? '').isNotEmpty)
        .take(_maxShown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(strings.agentResult(result.elements.length, result.packageName ?? '?'), style: summary),
        if (result.truncated)
          Text(strings.agentResultTruncated, style: TextStyle(color: c.muted, fontSize: 13)),
        for (final element in shown)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line, width: 0.5))),
            child: Text.rich(TextSpan(
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.4),
              children: [
                if (element.editable || element.clickable)
                  TextSpan(
                    text: '[${element.editable ? strings.agentRoleField : strings.agentRoleButton}] ',
                    style: TextStyle(color: c.brand),
                  ),
                TextSpan(text: (element.text ?? '').isNotEmpty ? element.text : element.description),
              ],
            )),
          ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed, required this.color, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: busy ? 1 : 0.45),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 10),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed, required this.color, required this.border});

  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: border),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
