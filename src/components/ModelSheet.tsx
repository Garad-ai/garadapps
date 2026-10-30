import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon } from '@/components/Icon';
import { useI18n } from '@/lib/i18n';
import { useModels } from '@/lib/models';
import { usePalette } from '@/lib/theme';

/** Bottom sheet listing the same models as the web picker; locked models show their plan. */
export function ModelSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const { models, selected, select } = useModels();

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel={t.cancel} />
      <View
        style={[
          styles.sheet,
          { backgroundColor: c.card, borderColor: c.line, paddingBottom: Math.max(insets.bottom, 16) },
        ]}>
        <View style={[styles.handle, { backgroundColor: c.surfaceStrong }]} />
        <Text style={[styles.title, { color: c.text }]}>{t.chooseModel}</Text>
        <ScrollView style={styles.list}>
          {models.map((model) => {
            const active = model.id === selected?.id;
            return (
              <Pressable
                key={model.id}
                accessibilityRole="button"
                accessibilityState={{ selected: active, disabled: model.locked }}
                disabled={model.locked}
                onPress={() => {
                  select(model.id);
                  onClose();
                }}
                style={({ pressed }) => [
                  styles.row,
                  { backgroundColor: pressed ? c.surface : 'transparent', opacity: model.locked ? 0.55 : 1 },
                ]}>
                <View style={styles.flex}>
                  <Text style={[styles.name, { color: c.text }]}>{model.displayName}</Text>
                  {model.locked ? (
                    <Text style={[styles.description, { color: c.faint }]}>
                      {t.lockedModel}
                      {model.requiredPlan ? `: ${model.requiredPlan}` : ''}
                    </Text>
                  ) : model.description ? (
                    <Text numberOfLines={2} style={[styles.description, { color: c.muted }]}>
                      {model.description}
                    </Text>
                  ) : null}
                </View>
                {model.locked ? (
                  <Icon name="lock" color={c.faint} size={15} />
                ) : active ? (
                  <Icon name="check" color={c.brand} size={18} />
                ) : null}
              </Pressable>
            );
          })}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.35)' },
  sheet: {
    maxHeight: '70%',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    paddingTop: 8,
  },
  handle: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, marginBottom: 12 },
  title: { fontSize: 17, fontWeight: '600', paddingHorizontal: 20, marginBottom: 8 },
  list: { paddingHorizontal: 8 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: 12,
  },
  name: { fontSize: 16, fontWeight: '500' },
  description: { fontSize: 13, lineHeight: 18, marginTop: 2 },
});
