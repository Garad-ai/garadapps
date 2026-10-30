import { Image, Pressable, StyleSheet, Text, View } from 'react-native';

import type { Palette } from '@/lib/theme';

type Props = {
  title: string;
  body: string;
  actionLabel?: string;
  onAction?: () => void;
  background: string;
  colors: Palette;
};

/** Full-screen message with one action: offline, maintenance or a required update. */
export function BlockingScreen({ title, body, actionLabel, onAction, background, colors: c }: Props) {
  return (
    <View
      style={[StyleSheet.absoluteFill, styles.container, { backgroundColor: background }]}
      accessibilityViewIsModal
    >
      <Image source={require('../../assets/images/splash-icon.png')} style={styles.mark} />
      <Text accessibilityRole="header" style={[styles.title, { color: c.text }]}>
        {title}
      </Text>
      <Text style={[styles.body, { color: c.muted }]}>{body}</Text>
      {actionLabel && onAction ? (
        <Pressable
          accessibilityRole="button"
          onPress={onAction}
          style={({ pressed }) => [styles.button, { backgroundColor: c.brand, opacity: pressed ? 0.85 : 1 }]}
        >
          <Text style={styles.buttonText}>{actionLabel}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', justifyContent: 'center', padding: 32, gap: 12 },
  mark: { width: 64, height: 64, marginBottom: 8 },
  title: { fontSize: 20, fontWeight: '700', textAlign: 'center' },
  body: { fontSize: 15, lineHeight: 21, textAlign: 'center' },
  button: { marginTop: 12, borderRadius: 14, paddingHorizontal: 26, paddingVertical: 14, minWidth: 180, alignItems: 'center' },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
