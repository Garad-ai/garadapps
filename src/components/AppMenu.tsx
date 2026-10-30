import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { AppConfig } from '@/lib/remoteConfig';
import { STRINGS } from '@/lib/strings';
import type { Palette } from '@/lib/theme';

type Props = {
  visible: boolean;
  onClose: () => void;
  config: AppConfig | null;
  version: string;
  updateNote: string | null;
  onTalk: () => void;
  onOpenLink: (url: string) => void;
  onCheckUpdates: () => void;
  colors: Palette;
  background: string;
};

/** Native bottom sheet opened from "Garad app" in the Chat Pro sidebar. */
export function AppMenu({
  visible,
  onClose,
  config,
  version,
  updateNote,
  onTalk,
  onOpenLink,
  onCheckUpdates,
  colors: c,
  background,
}: Props) {
  const insets = useSafeAreaInsets();

  const row = (label: string, onPress: () => void, accent = false) => (
    <Pressable
      key={label}
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.row, { backgroundColor: pressed ? c.surfaceStrong : 'transparent' }]}
    >
      <Text style={[styles.rowText, { color: accent ? c.brand : c.text, fontWeight: accent ? '700' : '500' }]}>
        {label}
      </Text>
    </Pressable>
  );

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel={STRINGS.close} />
      <View
        style={[
          styles.sheet,
          { backgroundColor: background, borderColor: c.line, paddingBottom: Math.max(insets.bottom, 16) },
        ]}
      >
        <View style={[styles.handle, { backgroundColor: c.surfaceStrong }]} />
        <Text accessibilityRole="header" style={[styles.title, { color: c.text }]}>
          {STRINGS.menuTitle}
        </Text>
        <ScrollView>
          {row(STRINGS.talkToGarad, onTalk, true)}
          {(config?.links ?? []).map((link) => row(link.label, () => onOpenLink(link.url)))}
          {row(STRINGS.checkForUpdates, onCheckUpdates)}
        </ScrollView>
        {updateNote ? <Text style={[styles.note, { color: c.muted }]}>{updateNote}</Text> : null}
        <Text style={[styles.version, { color: c.faint }]}>
          {STRINGS.version} {version}
        </Text>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.35)' },
  sheet: {
    maxHeight: '75%',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    paddingTop: 8,
    paddingHorizontal: 8,
  },
  handle: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, marginBottom: 12 },
  title: { fontSize: 18, fontWeight: '700', paddingHorizontal: 12, marginBottom: 6 },
  row: { minHeight: 50, justifyContent: 'center', paddingHorizontal: 12, borderRadius: 12 },
  rowText: { fontSize: 16 },
  note: { fontSize: 13, paddingHorizontal: 12, paddingTop: 8 },
  version: { fontSize: 12, paddingHorizontal: 12, paddingTop: 10 },
});
