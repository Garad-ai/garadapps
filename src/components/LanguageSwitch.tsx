import { Pressable, StyleSheet, Text, View } from 'react-native';

import { LANGUAGES, useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

export function LanguageSwitch() {
  const c = usePalette();
  const { language, setLanguage } = useI18n();

  return (
    <View style={[styles.group, { borderColor: c.line, backgroundColor: c.surface }]}>
      {LANGUAGES.map((item) => {
        const selected = item.code === language;
        return (
          <Pressable
            key={item.code}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            onPress={() => setLanguage(item.code)}
            style={[styles.option, selected && { backgroundColor: c.brand }]}>
            <Text style={{ color: selected ? c.brandText : c.text, fontWeight: '600' }}>
              {item.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  group: { flexDirection: 'row', borderRadius: 999, borderWidth: 1, padding: 3 },
  option: { paddingHorizontal: 14, paddingVertical: 7, borderRadius: 999 },
});
