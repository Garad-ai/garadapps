import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/billing.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/billing_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Billing: the website's plans (garad.ai/plans), the user's plan, and paying with EVC Plus.
void main() {
  test('EVC Plus numbers are sent as 252…, however they are typed', () {
    expect(evcPhone('61 234 5678'), '252612345678');
    expect(evcPhone('0612345678'), '252612345678');
    expect(evcPhone('+252 61 234 5678'), '252612345678');
    expect(evcPhone('00252612345678'), '252612345678');
  });

  test('prices look like the website: \$5, \$4.50', () {
    expect(GaradPlan.price(5), r'$5');
    expect(GaradPlan.price(4.5), r'$4.50');
  });

  test('reads the website\'s top models, toolkit and agents', () {
    final plan = GaradPlan.fromJson({
      'id': 'business',
      'name': 'Business',
      'monthlyPrice': 49,
      'flagships': [
        {'provider': 'Anthropic', 'name': 'Claude Opus 5.5', 'cost': 10},
      ],
      'tools': [
        {'key': 'video', 'label': 'Video', 'included': false},
      ],
      'agents': ['Deep research'],
    });
    expect(plan.team, isTrue, reason: 'the website treats "business" as a team plan');
    expect(plan.topModels.single.cost, 10);
    expect(plan.tools.single.included, isFalse);
    expect(plan.agents, ['Deep research']);
  });

  final plans = [
    {'id': '1', 'name': 'Basic', 'monthlyPrice': 0, 'description': 'Explore Garad AI for free', 'features': []},
    {
      'id': '5',
      'name': 'Standard',
      'monthlyPrice': 4.5,
      'description': 'For everyday chat.',
      'features': ['Smart AI chat'],
      'credits': 45,
      'flagships': [
        {'provider': 'Anthropic', 'name': 'Claude Sonnet 5.5', 'cost': 3},
        {'provider': 'OpenAI', 'name': 'GPT-6.1 Sol', 'cost': 10},
      ],
      'tools': [
        {'key': 'image', 'label': 'Images', 'included': true, 'detail': 'Credits'},
        {'key': 'video', 'label': 'Video', 'included': false},
      ],
      'agents': ['Deep research'],
    },
    {
      'id': '6',
      'name': 'Professional',
      'monthlyPrice': 15,
      'description': 'For creators.',
      'features': ['Everything in Standard'],
      'popular': true,
      'credits': 150,
    },
    {'id': '4', 'name': 'Business', 'monthlyPrice': 49, 'team': true, 'credits': 500, 'features': []},
  ];

  ({AuthState auth, List<Map<String, dynamic>> paid}) server({String? currentPlan}) {
    final paid = <Map<String, dynamic>>[];
    final api = GaradApi(
      client: MockClient((request) async {
        final path = request.url.path.replaceFirst(RegExp(r'^.*/api/mobile'), '');
        http.Response json(Object data, [int status = 200]) =>
            http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});
        switch (path) {
          case '/plans':
            return json({'data': plans});
          case '/payments/methods':
            return json({
              'data': [
                {'id': 'evc_plus', 'name': 'EVC Plus', 'requiresPhone': true, 'description': 'Hormuud wallet'},
              ],
            });
          case '/billing':
            return json({
              'plan': currentPlan == null ? null : {'id': currentPlan, 'name': 'Standard', 'monthlyPrice': 4.5},
              'endsAt': currentPlan == null ? null : '2026-12-25T10:00:00+00:00',
              'credits': currentPlan == null ? null : 30,
            });
          case '/payments/checkout':
            paid.add(jsonDecode(request.body) as Map<String, dynamic>);
            return json({'status': 'paid', 'message': 'Professional plan activated.'});
        }
        return json({'message': 'not found'}, 404);
      }),
    );
    return (auth: AuthState(api), paid: paid);
  }

  Future<void> open(WidgetTester tester, AuthState auth) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: const MaterialApp(home: BillingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one plan at a time with a switcher, like ChatGPT', (tester) async {
    final fake = server(currentPlan: '5');
    await open(tester, fake.auth);
    expect(find.text('Upgrade your plan'), findsOneWidget);
    expect(find.textContaining('Your plan: Standard · 30 credits left'), findsOneWidget);
    // Opens on the popular plan they don't have: Professional (pill + heading).
    expect(find.text('Professional'), findsNWidgets(2));
    expect(find.text(r'$15'), findsOneWidget);
    expect(find.text('150 credits a month'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Get Professional'), findsOneWidget);

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    expect(find.text(r'$4.50'), findsOneWidget, reason: 'the website price, as the server sends it');
    expect(find.text('Your current plan'), findsOneWidget, reason: 'Standard is theirs: no buy button');

    await tester.tap(find.text('Basic'));
    await tester.pumpAndSettle();
    expect(find.text('Free'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing, reason: 'nothing to buy on the free plan');

    await tester.tap(find.text('Business').first);
    await tester.pumpAndSettle();
    expect(find.text('USD / person\n/ month'), findsOneWidget);
  });

  testWidgets('no plan: Basic (free) is current; choosing a plan pays with EVC Plus', (tester) async {
    final fake = server();
    await open(tester, fake.auth);
    expect(find.text('Your plan: Free'), findsOneWidget);

    await tester.tap(find.text('Basic'));
    await tester.pumpAndSettle();
    expect(find.text('Your current plan'), findsOneWidget, reason: 'Basic is theirs');

    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Professional'));
    await tester.pumpAndSettle();
    expect(find.text('Pay for Professional'), findsOneWidget);

    // Empty field: ask for the number.
    await tester.tap(find.text(r'Pay $15'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your EVC Plus number.'), findsOneWidget);
    expect(fake.paid, isEmpty);

    // Typing clears the message; a number that is too short is refused.
    await tester.enterText(find.byType(TextField), '61 234');
    await tester.pump();
    expect(find.text('Enter your EVC Plus number.'), findsNothing);
    await tester.tap(find.text(r'Pay $15'));
    await tester.pumpAndSettle();
    expect(find.textContaining('valid EVC Plus number'), findsOneWidget);
    expect(fake.paid, isEmpty);

    await tester.enterText(find.byType(TextField), '061 234 5678');
    await tester.tap(find.text(r'Pay $15'));
    await tester.pumpAndSettle();
    expect(fake.paid.single, {'planId': '6', 'method': 'evc_plus', 'phone': '252612345678'});
    expect(find.text('Professional plan activated.'), findsOneWidget);
  });
}
