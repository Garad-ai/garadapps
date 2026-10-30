import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, AppState, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import * as GaradAgent from '../../modules/garad-agent';
import type { ScreenReadResult } from '../../modules/garad-agent';
import { STRINGS } from '@/lib/strings';
import { useIsDark, usePalette } from '@/lib/theme';

type Status = 'off' | 'starting' | 'on';

const TEST_DELAY_MS = 5000;
const MAX_SHOWN = 80;

function readStatus(): Status {
  if (GaradAgent.isConnected()) return 'on';
  return GaradAgent.isEnabled() ? 'starting' : 'off';
}

/**
 * Consent and controls for the Garad agent (docs/AGENT_PLAN.md): explains what
 * it reads and the safety rules before the user is sent to Accessibility settings, shows
 * whether it is on, and has a read test for testers.
 */
export default function AgentScreen() {
  const c = usePalette();
  const isDark = useIsDark();
  const [status, setStatus] = useState<Status>(readStatus);
  const [consent, setConsent] = useState(false);
  const [reading, setReading] = useState(false);
  const [result, setResult] = useState<ScreenReadResult | null>(null);

  const [notifications, setNotifications] = useState(GaradAgent.isNotificationAccessEnabled);
  const [announce, setAnnounce] = useState(GaradAgent.getAnnounceAloud);

  const refresh = useCallback(() => {
    setStatus(readStatus());
    setNotifications(GaradAgent.isNotificationAccessEnabled());
  }, []);

  // The user turns the service on in system settings, so re-check whenever Garad comes back.
  // The service connects a moment after it is switched on, hence the second check.
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const subscription = AppState.addEventListener('change', (state) => {
      if (state !== 'active') return;
      refresh();
      clearTimeout(timer);
      timer = setTimeout(refresh, 1200);
    });
    return () => {
      subscription.remove();
      clearTimeout(timer);
    };
  }, [refresh]);

  const testRead = async () => {
    setReading(true);
    setResult(null);
    try {
      setResult(await GaradAgent.readScreen(TEST_DELAY_MS));
    } finally {
      setReading(false);
      refresh();
    }
  };

  const turnOff = () => {
    GaradAgent.disable();
    setResult(null);
    setTimeout(refresh, 300);
  };

  const card = [styles.card, { backgroundColor: c.surface, borderColor: c.line }];

  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: c.background }]} edges={['top', 'bottom']}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={styles.header}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={STRINGS.back}
          onPress={() => (router.canGoBack() ? router.back() : router.replace('/'))}
          hitSlop={12}
          style={styles.backButton}
        >
          <Text style={[styles.backText, { color: c.text }]}>‹</Text>
        </Pressable>
        <Text accessibilityRole="header" style={[styles.headerTitle, { color: c.text }]}>
          {STRINGS.agentTitle}
        </Text>
      </View>

      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.intro, { color: c.text }]}>{STRINGS.agentIntro}</Text>

        {!GaradAgent.isSupported ? (
          <View style={card}>
            <Text style={[styles.body, { color: c.muted }]}>{STRINGS.agentUnsupported}</Text>
          </View>
        ) : (
          <>
            <View style={card}>
              <Text accessibilityRole="header" style={[styles.cardTitle, { color: c.text }]}>
                {STRINGS.agentReadsTitle}
              </Text>
              <Text style={[styles.body, { color: c.muted }]}>{STRINGS.agentReadsBody}</Text>
            </View>

            <View style={card}>
              <Text accessibilityRole="header" style={[styles.cardTitle, { color: c.text }]}>
                {STRINGS.agentRulesTitle}
              </Text>
              {STRINGS.agentRules.map((rule) => (
                <View key={rule} style={styles.ruleRow}>
                  <Text style={[styles.bullet, { color: c.brand }]}>•</Text>
                  <Text style={[styles.body, styles.flex, { color: c.muted }]}>{rule}</Text>
                </View>
              ))}
            </View>

            <View style={card} accessible accessibilityLiveRegion="polite">
              <View style={styles.statusRow}>
                <View
                  style={[
                    styles.dot,
                    { backgroundColor: status === 'on' ? '#2e9d5b' : status === 'starting' ? '#d99a1e' : c.faint },
                  ]}
                />
                <Text style={[styles.cardTitle, styles.statusText, { color: c.text }]}>
                  {STRINGS.agentTitle}:{' '}
                  {status === 'on'
                    ? STRINGS.agentStatusOn
                    : status === 'starting'
                      ? STRINGS.agentStatusStarting
                      : STRINGS.agentStatusOff}
                </Text>
              </View>
            </View>

            {status === 'off' ? (
              <>
                <Pressable
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: consent }}
                  onPress={() => setConsent((value) => !value)}
                  style={styles.consentRow}
                >
                  <View
                    style={[
                      styles.checkbox,
                      { borderColor: consent ? c.brand : c.faint, backgroundColor: consent ? c.brand : 'transparent' },
                    ]}
                  >
                    {consent ? <Text style={styles.checkmark}>✓</Text> : null}
                  </View>
                  <Text style={[styles.consentText, { color: c.text }]}>{STRINGS.agentConsent}</Text>
                </Pressable>
                <PrimaryButton
                  label={STRINGS.agentOpenSettings}
                  disabled={!consent}
                  onPress={GaradAgent.openSettings}
                  color={c.brand}
                />
                <Text style={[styles.hint, { color: c.muted }]}>{STRINGS.agentSettingsHint}</Text>
              </>
            ) : (
              <>
                <View style={card}>
                  <Text accessibilityRole="header" style={[styles.cardTitle, { color: c.text }]}>
                    {STRINGS.agentTestTitle}
                  </Text>
                  <Text style={[styles.body, { color: c.muted }]}>{STRINGS.agentTestHint}</Text>
                  <PrimaryButton
                    label={reading ? STRINGS.agentTestWaiting : STRINGS.agentTestButton}
                    disabled={reading || status !== 'on'}
                    onPress={testRead}
                    color={c.brand}
                    busy={reading}
                  />
                  {result ? <ReadResult result={result} /> : null}
                </View>
                <SecondaryButton label={STRINGS.agentTurnOff} onPress={turnOff} color={c.danger} border={c.line} />
                <SecondaryButton
                  label={STRINGS.agentOpenSettings}
                  onPress={GaradAgent.openSettings}
                  color={c.text}
                  border={c.line}
                />
              </>
            )}

            <View style={card}>
              <Text accessibilityRole="header" style={[styles.cardTitle, { color: c.text }]}>
                {STRINGS.agentMessagesTitle}
              </Text>
              <Text style={[styles.body, { color: c.muted }]}>{STRINGS.agentMessagesBody}</Text>
              <View style={styles.statusRow} accessible accessibilityLiveRegion="polite">
                <View style={[styles.dot, { backgroundColor: notifications ? '#2e9d5b' : c.faint }]} />
                <Text style={[styles.body, styles.statusText, { color: c.text }]}>
                  {notifications ? STRINGS.agentMessagesOn : STRINGS.agentMessagesOff}
                </Text>
              </View>
              <SecondaryButton
                label={STRINGS.agentMessagesOpen}
                onPress={GaradAgent.openNotificationSettings}
                color={c.text}
                border={c.line}
              />
              {notifications ? (
                <View style={styles.switchRow}>
                  <Text style={[styles.body, styles.flex, { color: c.text }]}>{STRINGS.agentAnnounce}</Text>
                  <Switch
                    accessibilityLabel={STRINGS.agentAnnounce}
                    value={announce}
                    onValueChange={(value) => {
                      GaradAgent.setAnnounceAloud(value);
                      setAnnounce(value);
                    }}
                    trackColor={{ true: c.brand, false: c.surfaceStrong }}
                  />
                </View>
              ) : null}
            </View>
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function ReadResult({ result }: { result: ScreenReadResult }) {
  const c = usePalette();

  if (!result.available) {
    const message =
      result.reason === 'blocked_app'
        ? STRINGS.agentReasonBlocked
        : result.reason === 'no_window'
          ? STRINGS.agentReasonNoWindow
          : result.reason === 'unsupported'
            ? STRINGS.agentUnsupported
            : STRINGS.agentReasonOff;
    return <Text style={[styles.resultSummary, { color: c.text }]}>{message}</Text>;
  }

  const shown = result.elements.filter((element) => element.text || element.description).slice(0, MAX_SHOWN);
  return (
    <View style={styles.result}>
      <Text style={[styles.resultSummary, { color: c.text }]}>
        {STRINGS.agentResult(result.elements.length, result.package ?? '?')}
      </Text>
      {result.truncated ? <Text style={[styles.hint, { color: c.muted }]}>{STRINGS.agentResultTruncated}</Text> : null}
      {shown.map((element) => {
        const kind = element.editable ? STRINGS.agentRoleField : element.clickable ? STRINGS.agentRoleButton : null;
        return (
          <Text key={element.id} style={[styles.element, { color: c.muted, borderColor: c.line }]}>
            {kind ? <Text style={{ color: c.brand }}>[{kind}] </Text> : null}
            {element.text || element.description}
          </Text>
        );
      })}
    </View>
  );
}

function PrimaryButton({
  label,
  onPress,
  color,
  disabled = false,
  busy = false,
}: {
  label: string;
  onPress: () => void;
  color: string;
  disabled?: boolean;
  busy?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled, busy }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.primary,
        { backgroundColor: color, opacity: disabled && !busy ? 0.45 : pressed ? 0.85 : 1 },
      ]}
    >
      {busy ? <ActivityIndicator color="#fff" /> : null}
      <Text style={styles.primaryText}>{label}</Text>
    </Pressable>
  );
}

function SecondaryButton({
  label,
  onPress,
  color,
  border,
}: {
  label: string;
  onPress: () => void;
  color: string;
  border: string;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.secondary, { borderColor: border, opacity: pressed ? 0.7 : 1 }]}
    >
      <Text style={[styles.secondaryText, { color }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, height: 52 },
  backButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  backText: { fontSize: 34, lineHeight: 38, fontWeight: '300' },
  headerTitle: { fontSize: 18, fontWeight: '700' },
  content: { padding: 16, paddingBottom: 40, gap: 14 },
  intro: { fontSize: 17, lineHeight: 25 },
  card: { borderRadius: 18, borderWidth: StyleSheet.hairlineWidth, padding: 16, gap: 8 },
  cardTitle: { fontSize: 16, fontWeight: '700' },
  body: { fontSize: 15, lineHeight: 22 },
  ruleRow: { flexDirection: 'row', gap: 8 },
  bullet: { fontSize: 15, lineHeight: 22, fontWeight: '700' },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 48 },
  statusText: { flex: 1 },
  dot: { width: 12, height: 12, borderRadius: 6 },
  consentRow: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 48 },
  checkbox: { width: 26, height: 26, borderRadius: 7, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  checkmark: { color: '#fff', fontSize: 16, fontWeight: '700' },
  consentText: { flex: 1, fontSize: 16, fontWeight: '500' },
  primary: {
    flexDirection: 'row',
    gap: 10,
    minHeight: 52,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
  },
  primaryText: { color: '#fff', fontSize: 16, fontWeight: '600', textAlign: 'center' },
  secondary: {
    minHeight: 50,
    borderRadius: 16,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
  },
  secondaryText: { fontSize: 16, fontWeight: '600' },
  hint: { fontSize: 13, lineHeight: 19 },
  result: { gap: 6, marginTop: 4 },
  resultSummary: { fontSize: 15, fontWeight: '600', marginTop: 4 },
  element: { fontSize: 14, lineHeight: 20, borderTopWidth: StyleSheet.hairlineWidth, paddingTop: 6 },
});
