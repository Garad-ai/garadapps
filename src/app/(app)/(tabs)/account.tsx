import { useFocusEffect } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { LanguageSwitch } from '@/components/LanguageSwitch';
import { Button, Notice } from '@/components/ui';
import { deleteAccount, getProfile, getUsage, Profile, Usage } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { PRIVACY_URL, TERMS_URL } from '@/lib/config';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

export default function AccountScreen() {
  const c = usePalette();
  const { t } = useI18n();
  const { signOut } = useAuth();

  const [profile, setProfile] = useState<Profile | null>(null);
  const [usage, setUsage] = useState<Usage | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  useFocusEffect(
    useCallback(() => {
      Promise.all([getProfile(), getUsage()])
        .then(([nextProfile, nextUsage]) => {
          setProfile(nextProfile);
          setUsage(nextUsage);
          setError(null);
        })
        .catch((e) => setError(errorMessage(e, t)));
    }, [t])
  );

  const credits = (value: Usage['remaining_words']) => {
    if (value === undefined || value === null) return '—';
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0) return t.unlimited;
    return number.toLocaleString();
  };

  const confirmDelete = () => {
    Alert.alert(t.deleteAccount, t.deleteAccountConfirm, [
      { text: t.cancel, style: 'cancel' },
      {
        text: t.delete,
        style: 'destructive',
        onPress: async () => {
          setDeleting(true);
          try {
            await deleteAccount();
            await signOut({ revoke: false });
          } catch (e) {
            setDeleting(false);
            Alert.alert(errorMessage(e, t));
          }
        },
      },
    ]);
  };

  const fullName = [profile?.name, profile?.surname].filter(Boolean).join(' ');

  return (
    <ScrollView
      style={{ backgroundColor: c.background }}
      contentContainerStyle={styles.content}>
      {error && <Notice tone="error">{error}</Notice>}

      <View style={[styles.card, { backgroundColor: c.surface, borderColor: c.line }]}>
        <View style={[styles.avatar, { backgroundColor: c.brand }]}>
          <Text style={styles.avatarText}>{(profile?.name ?? '?').slice(0, 1).toUpperCase()}</Text>
        </View>
        <View style={styles.flex}>
          <Text style={[styles.name, { color: c.text }]}>{fullName || '—'}</Text>
          <Text style={{ color: c.muted }}>{profile?.email ?? ''}</Text>
        </View>
      </View>

      <View style={[styles.card, styles.column, { backgroundColor: c.surface, borderColor: c.line }]}>
        <Row label={t.plan} value={usage?.plan_name || t.freePlan} />
        <Row label={t.wordCredits} value={credits(usage?.remaining_words)} />
        <Row label={t.imageCredits} value={credits(usage?.remaining_images)} />
      </View>

      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: c.muted }]}>{t.language}</Text>
        <LanguageSwitch />
      </View>

      <View style={[styles.card, styles.column, { backgroundColor: c.surface, borderColor: c.line }]}>
        <LinkRow label={t.privacy} onPress={() => WebBrowser.openBrowserAsync(PRIVACY_URL)} />
        <LinkRow label={t.terms} onPress={() => WebBrowser.openBrowserAsync(TERMS_URL)} />
      </View>

      <Button title={t.signOut} variant="secondary" onPress={() => signOut()} />
      <Button title={t.deleteAccount} variant="danger" onPress={confirmDelete} loading={deleting} />
    </ScrollView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  const c = usePalette();
  return (
    <View style={styles.row}>
      <Text style={{ color: c.muted, fontSize: 15 }}>{label}</Text>
      <Text style={{ color: c.text, fontSize: 15, fontWeight: '600' }}>{value}</Text>
    </View>
  );
}

function LinkRow({ label, onPress }: { label: string; onPress: () => void }) {
  const c = usePalette();
  return (
    <Pressable accessibilityRole="link" onPress={onPress} style={styles.row}>
      <Text style={{ color: c.text, fontSize: 15 }}>{label}</Text>
      <Text style={{ color: c.faint, fontSize: 18 }}>›</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 16, maxWidth: 720, width: '100%', alignSelf: 'center' },
  flex: { flex: 1 },
  card: {
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  column: { flexDirection: 'column', alignItems: 'stretch', gap: 12 },
  avatar: { width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: '#fff', fontSize: 22, fontWeight: '700' },
  name: { fontSize: 18, fontWeight: '700' },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 28 },
  section: { gap: 8, alignItems: 'flex-start' },
  sectionTitle: { fontSize: 13, fontWeight: '600', textTransform: 'uppercase' },
});
