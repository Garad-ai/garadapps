import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Markdown } from '@/components/Markdown';
import { Button, Notice } from '@/components/ui';
import { getMessages, messageText, sendMessage } from '@/lib/api';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

type Bubble = { key: string; role: 'user' | 'assistant'; text: string; pending?: boolean };

export default function ChatScreen() {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ id: string; title?: string }>();
  const conversationId = Number(params.id);

  const [bubbles, setBubbles] = useState<Bubble[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [sendError, setSendError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const listRef = useRef<FlatList<Bubble>>(null);
  const abortRef = useRef<AbortController | null>(null);

  const load = useCallback(async () => {
    try {
      const messages = await getMessages(conversationId);
      const next: Bubble[] = [];
      for (const message of messages) {
        if (message.input) next.push({ key: `u${message.id}`, role: 'user', text: message.input });
        const reply = messageText(message);
        if (reply) next.push({ key: `a${message.id}`, role: 'assistant', text: reply });
      }
      setBubbles(next);
      setLoadError(null);
    } catch (e) {
      setLoadError(errorMessage(e, t));
    }
  }, [conversationId, t]);

  useEffect(() => {
    void load();
    return () => abortRef.current?.abort();
  }, [load]);

  const send = async () => {
    const prompt = draft.trim();
    if (!prompt || streaming) return;
    const stamp = Date.now();
    const replyKey = `p${stamp}`;
    setDraft('');
    setSendError(null);
    setStreaming(true);
    setBubbles((current) => [
      ...(current ?? []),
      { key: `q${stamp}`, role: 'user', text: prompt },
      { key: replyKey, role: 'assistant', text: '', pending: true },
    ]);
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);

    const controller = new AbortController();
    abortRef.current = controller;
    try {
      await sendMessage(conversationId, prompt, {
        signal: controller.signal,
        onDelta: (delta) =>
          setBubbles((current) =>
            (current ?? []).map((bubble) =>
              bubble.key === replyKey ? { ...bubble, text: bubble.text + delta } : bubble
            )
          ),
      });
    } catch (e) {
      if (!controller.signal.aborted) setSendError(errorMessage(e, t));
    } finally {
      setBubbles((current) =>
        (current ?? [])
          .map((bubble) => (bubble.key === replyKey ? { ...bubble, pending: false } : bubble))
          .filter((bubble) => bubble.key !== replyKey || bubble.text.length > 0)
      );
      abortRef.current = null;
      setStreaming(false);
    }
  };

  const stop = () => abortRef.current?.abort();

  const copy = async (bubble: Bubble) => {
    await Clipboard.setStringAsync(bubble.text);
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setCopiedKey(bubble.key);
    setTimeout(() => setCopiedKey((key) => (key === bubble.key ? null : key)), 1500);
  };

  return (
    <KeyboardAvoidingView
      style={[styles.flex, { backgroundColor: c.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? insets.top + 44 : 0}>
      <Stack.Screen options={{ title: params.title ?? '' }} />

      {bubbles === null && !loadError ? (
        <View style={styles.center}>
          <ActivityIndicator color={c.brand} />
        </View>
      ) : loadError ? (
        <View style={styles.errorBox}>
          <Notice tone="error">{loadError}</Notice>
          <Button title={t.retry} variant="secondary" onPress={load} />
        </View>
      ) : (
        <FlatList
          ref={listRef}
          style={styles.flex}
          contentContainerStyle={styles.messages}
          data={bubbles ?? []}
          keyExtractor={(item) => item.key}
          onContentSizeChange={() => listRef.current?.scrollToEnd({ animated: true })}
          keyboardDismissMode="interactive"
          renderItem={({ item }) =>
            item.role === 'user' ? (
              <Pressable onLongPress={() => copy(item)} style={styles.userRow}>
                <View style={[styles.userBubble, { backgroundColor: c.userBubble }]}>
                  <Text selectable style={[styles.userText, { color: c.userBubbleText }]}>
                    {item.text}
                  </Text>
                </View>
              </Pressable>
            ) : (
              <Pressable onLongPress={() => copy(item)} style={styles.assistant}>
                {item.pending && item.text.length === 0 ? (
                  <ActivityIndicator color={c.brand} style={styles.typing} />
                ) : (
                  <Markdown text={item.text} />
                )}
                {copiedKey === item.key && (
                  <Text style={{ color: c.faint, fontSize: 12 }}>{t.copied}</Text>
                )}
              </Pressable>
            )
          }
        />
      )}

      {sendError && (
        <View style={styles.sendError}>
          <Notice tone="error">{sendError}</Notice>
        </View>
      )}

      <View
        style={[
          styles.composer,
          { borderTopColor: c.line, paddingBottom: Math.max(insets.bottom, 10) },
        ]}>
        <TextInput
          value={draft}
          onChangeText={setDraft}
          placeholder={t.messagePlaceholder}
          placeholderTextColor={c.faint}
          multiline
          style={[styles.input, { color: c.text, backgroundColor: c.surface, borderColor: c.line }]}
        />
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={streaming ? t.stop : t.send}
          onPress={streaming ? stop : send}
          disabled={!streaming && draft.trim().length === 0}
          style={({ pressed }) => [
            styles.sendButton,
            {
              backgroundColor: c.brand,
              opacity: !streaming && draft.trim().length === 0 ? 0.4 : pressed ? 0.8 : 1,
            },
          ]}>
          <Text style={{ color: c.brandText, fontWeight: '700' }}>{streaming ? '■' : '↑'}</Text>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  errorBox: { flex: 1, padding: 16, gap: 10 },
  messages: { padding: 16, gap: 18 },
  userRow: { alignItems: 'flex-end' },
  userBubble: { maxWidth: '85%', borderRadius: 18, paddingHorizontal: 14, paddingVertical: 10 },
  userText: { fontSize: 16, lineHeight: 22 },
  assistant: { gap: 6 },
  typing: { alignSelf: 'flex-start' },
  sendError: { paddingHorizontal: 16, paddingBottom: 8 },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 10,
    paddingHorizontal: 12,
    paddingTop: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  input: {
    flex: 1,
    minHeight: 44,
    maxHeight: 140,
    borderRadius: 22,
    borderWidth: 1,
    paddingHorizontal: 16,
    paddingTop: 11,
    paddingBottom: 11,
    fontSize: 16,
  },
  sendButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
