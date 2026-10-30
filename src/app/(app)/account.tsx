import { useFocusEffect } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { LanguageSwitch } from '@/components/LanguageSwitch';
import { Button, Notice } from '@/components/ui';
import { useAccount } from '@/lib/account';
import { deleteAccount } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { PRIVACY_URL, TERMS_URL } from '@/lib/config';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { serif, usePalette } from '@/lib/theme';

export default function AccountScreen() {
  const c = usePalette();
  const { t } = useI18n();
  const { signOut } = useAuth();

  const { account, error: loadError, refresh } = useAccount();
  const [deleting, setDeleting] = useState(false);

  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh])
  );

  const error = loadError ? errorMessage(loadError, t) : null;
  const messages = account?.usage?.messages;
  const messagesValue = !messages
    ? '—'
    : messages.limit > 0
      ? `${messages.used.toLocaleString()} / ${messages.limit.toLocaleString()}`
      : `${messages.used.toLocaleString()} · ${t.unlimited}`;

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

  const user = account?.user;
  const fullName = user?.name || [user?.givenName, user?.surname].filter(Boolean).join(' ');

  return (
    <ScrollView
      style={{ backgroundColor: c.background }}
      contentContainerStyle={styles.content}>
      {error && <Notice tone="error">{error}</Notice>}

      <View style={[styles.card, { backgroundColor: c.card, borderColor: c.line }]}>
        <View style={[styles.avatar, { backgroundColor: c.text }]}>
          <Text style={[styles.avatarText, { color: c.background }]}>
            {(fullName || '?').slice(0, 1).toUpperCase()}
          </Text>
        </View>
        <View style={styles.flex}>
          <Text style={[styles.name, { color: c.text }]}>{fullName || '—'}</Text>
          <Text style={{ color: c.muted }}>{user?.email ?? ''}</Text>
        </View>
      </View>

      <View style={[styles.card, styles.column, { backgroundColor: c.card, borderColor: c.line }]}>
        <Row label={t.plan} value={account?.subscription?.planId || t.freePlan} />
        <Row label={t.messagesUsed} value={messagesValue} />
      </View>

      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: c.muted }]}>{t.language}</Text>
        <LanguageSwitch />
      </View>

      <View style={[styles.card, styles.column, { backgroundColor: c.card, borderColor: c.line }]}>
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
  avatarText: { fontSize: 22, fontWeight: '700' },
  name: { fontFamily: serif, fontSize: 20 },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 28 },
  section: { gap: 8, alignItems: 'flex-start' },
  sectionTitle: { fontSize: 13, fontWeight: '600', textTransform: 'uppercase' },
});
