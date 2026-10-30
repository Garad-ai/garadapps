import { Image } from 'expo-image';
import { ReactNode } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { LanguageSwitch } from '@/components/LanguageSwitch';
import { useI18n } from '@/lib/i18n';
import { serif, usePalette } from '@/lib/theme';

/** Shared frame for the sign-in, sign-up and password reset screens. */
export function AuthScreen({ title, children }: { title: string; children: ReactNode }) {
  const c = usePalette();
  const { t } = useI18n();

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: c.background }]}>
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          <View style={styles.top}>
            <LanguageSwitch />
          </View>
          <View style={styles.brand}>
            <Image
              source={require('../../assets/images/wordmark.png')}
              style={styles.wordmark}
              contentFit="contain"
              accessibilityLabel="Garad AI"
            />
            <Text style={[styles.tagline, { color: c.muted }]}>{t.appTagline}</Text>
          </View>
          <Text style={[styles.title, { color: c.text }]}>{title}</Text>
          <View style={styles.form}>{children}</View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1 },
  flex: { flex: 1 },
  content: { flexGrow: 1, padding: 24, gap: 20, maxWidth: 480, width: '100%', alignSelf: 'center' },
  top: { alignItems: 'flex-end' },
  brand: { alignItems: 'center', gap: 10, marginTop: 12 },
  wordmark: { width: 200, height: 56 },
  tagline: { textAlign: 'center', fontSize: 14, lineHeight: 20 },
  title: { fontFamily: serif, fontSize: 30, marginTop: 8 },
  form: { gap: 14 },
});
