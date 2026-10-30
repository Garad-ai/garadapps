import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { Palette } from '@/lib/theme';

type Props = {
  message: string;
  actionLabel?: string;
  onAction?: () => void;
  onDismiss: () => void;
  dismissLabel: string;
  colors: Palette;
};

/** A slim notice above the page: an announcement or an available update. */
export function Banner({ message, actionLabel, onAction, onDismiss, dismissLabel, colors: c }: Props) {
  return (
    <View
      accessibilityRole="alert"
      style={[styles.banner, { backgroundColor: c.brandSoft, borderColor: c.line }]}
    >
      <Text style={[styles.message, { color: c.text }]}>{message}</Text>
      {actionLabel && onAction ? (
        <Pressable accessibilityRole="button" onPress={onAction} hitSlop={8} style={styles.action}>
          <Text style={[styles.actionText, { color: c.brand }]}>{actionLabel}</Text>
        </Pressable>
      ) : null}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={dismissLabel}
        onPress={onDismiss}
        hitSlop={10}
        style={styles.dismiss}
      >
        <Text style={[styles.dismissText, { color: c.muted }]}>✕</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  message: { flex: 1, fontSize: 14, lineHeight: 19 },
  action: { paddingHorizontal: 4 },
  actionText: { fontSize: 14, fontWeight: '700' },
  dismiss: { paddingHorizontal: 4 },
  dismissText: { fontSize: 16 },
});
