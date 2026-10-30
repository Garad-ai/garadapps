import { Image } from 'expo-image';
import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Share,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';

import { Button, Field, Notice } from '@/components/ui';
import { generateImage, GeneratedImage, getRecentImages } from '@/lib/api';
import { absoluteUrl } from '@/lib/config';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

const COLUMNS = 2;
const GAP = 10;
const PADDING = 16;

export default function ImagesScreen() {
  const c = usePalette();
  const { t } = useI18n();
  const { width } = useWindowDimensions();
  const tile = (Math.min(width, 720) - PADDING * 2 - GAP * (COLUMNS - 1)) / COLUMNS;

  const [prompt, setPrompt] = useState('');
  const [images, setImages] = useState<GeneratedImage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useFocusEffect(
    useCallback(() => {
      getRecentImages()
        .then(setImages)
        .catch((e) => setError(errorMessage(e, t)));
    }, [t])
  );

  const generate = async () => {
    if (!prompt.trim()) {
      setError(t.required);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const created = await generateImage(prompt.trim());
      setImages((current) => [...created, ...current]);
      setPrompt('');
    } catch (e) {
      setError(errorMessage(e, t));
    } finally {
      setLoading(false);
    }
  };

  const share = (url: string) => {
    void Share.share(Platform.OS === 'ios' ? { url } : { message: url });
  };

  return (
    <KeyboardAvoidingView
      style={[styles.flex, { backgroundColor: c.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <FlatList
        data={images}
        numColumns={COLUMNS}
        keyExtractor={(item) => String(item.id)}
        contentContainerStyle={styles.content}
        columnWrapperStyle={{ gap: GAP }}
        keyboardShouldPersistTaps="handled"
        ListHeaderComponent={
          <View style={styles.form}>
            <Field
              label={t.images}
              value={prompt}
              onChangeText={setPrompt}
              placeholder={t.imagePrompt}
              multiline
              style={styles.prompt}
            />
            <Button
              title={loading ? t.generating : t.generate}
              onPress={generate}
              loading={loading}
            />
            {error && <Notice tone="error">{error}</Notice>}
            {images.length > 0 && (
              <Text style={[styles.section, { color: c.text }]}>{t.recentImages}</Text>
            )}
          </View>
        }
        ListEmptyComponent={
          <Text style={[styles.empty, { color: c.muted }]}>{t.noImages}</Text>
        }
        renderItem={({ item }) => {
          const url = absoluteUrl(item.output);
          if (!url) return null;
          return (
            <Pressable
              accessibilityRole="imagebutton"
              accessibilityLabel={item.input ?? t.share}
              onPress={() => share(url)}
              style={{ marginBottom: GAP }}>
              <Image
                source={{ uri: url }}
                style={[styles.image, { width: tile, height: tile, backgroundColor: c.surface }]}
                contentFit="cover"
                transition={200}
              />
            </Pressable>
          );
        }}
      />
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { padding: PADDING, maxWidth: 720, width: '100%', alignSelf: 'center' },
  form: { gap: 12, marginBottom: 16 },
  prompt: { minHeight: 96, paddingTop: 12, textAlignVertical: 'top' },
  section: { fontSize: 17, fontWeight: '700', marginTop: 8 },
  empty: { textAlign: 'center', marginTop: 24, fontSize: 15 },
  image: { borderRadius: 12 },
});
