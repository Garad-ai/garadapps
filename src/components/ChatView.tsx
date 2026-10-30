import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import { Image } from 'expo-image';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon } from '@/components/Icon';
import { Markdown } from '@/components/Markdown';
import { Button, Notice } from '@/components/ui';
import { createConversation, generateTitle, getMessages, messageText, sendMessage } from '@/lib/api';
import { useConversations } from '@/lib/conversations';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

type Bubble = { key: string; role: 'user' | 'assistant'; text: string; pending?: boolean };

/**
 * A ChatGPT-style conversation. Without `conversationId` it starts empty with a
 * greeting and suggestions, and creates the conversation on the first message.
 */
export function ChatView({ conversationId }: { conversationId?: number }) {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const conversations = useConversations();

  const [chatId, setChatId] = useState<number | undefined>(conversationId);
  const [bubbles, setBubbles] = useState<Bubble[] | null>(conversationId ? null : []);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [sendError, setSendError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const listRef = useRef<FlatList<Bubble>>(null);
  const abortRef = useRef<AbortController | null>(null);

  const load = useCallback(async () => {
    if (!conversationId) return;
    try {
      const messages = await getMessages(conversationId);
      const next: Bubble[] = [];
      for (const message of messages) {
        // The first stored message is the assistant's canned greeting; skip it like the web chat.
        if (!message.input) continue;
        next.push({ key: `u${message.id}`, role: 'user', text: message.input });
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

  const send = async (text?: string) => {
    const prompt = (text ?? draft).trim();
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
    const isFirstMessage = (bubbles?.length ?? 0) === 0;
    let id = chatId;
    try {
      if (!id) {
        id = await createConversation();
        setChatId(id);
      }
      const messageId = await sendMessage(id, prompt, {
        signal: controller.signal,
        onDelta: (delta) =>
          setBubbles((current) =>
            (current ?? []).map((bubble) =>
              bubble.key === replyKey ? { ...bubble, text: bubble.text + delta } : bubble
            )
          ),
      });
      if (isFirstMessage) {
        const conversation = id;
        void conversations.refresh();
        generateTitle(messageId)
          .then((title) => title && conversations.setTitle(conversation, title))
          .catch(() => undefined);
      }
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

  const copy = async (bubble: Bubble) => {
    await Clipboard.setStringAsync(bubble.text);
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setCopiedKey(bubble.key);
    setTimeout(() => setCopiedKey((key) => (key === bubble.key ? null : key)), 1500);
  };

  const empty = bubbles !== null && bubbles.length === 0;
  const canSend = draft.trim().length > 0;

  return (
    <KeyboardAvoidingView
      style={[styles.flex, { backgroundColor: c.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? insets.top + 44 : 0}>
      {bubbles === null && !loadError ? (
        <View style={styles.center}>
          <ActivityIndicator color={c.brand} />
        </View>
      ) : loadError ? (
        <View style={styles.errorBox}>
          <Notice tone="error">{loadError}</Notice>
          <Button title={t.retry} variant="secondary" onPress={load} />
        </View>
      ) : empty ? (
        <ScrollView contentContainerStyle={styles.welcome} keyboardShouldPersistTaps="handled">
          <Image
            source={require('../../assets/images/splash-icon.png')}
            style={styles.mark}
            contentFit="contain"
            accessibilityIgnoresInvertColors
          />
          <Text style={[styles.greeting, { color: c.text }]}>{t.greeting}</Text>
          <View style={styles.suggestions}>
            {t.suggestions.map((suggestion) => (
              <Pressable
                key={suggestion}
                accessibilityRole="button"
                onPress={() => send(suggestion)}
                style={({ pressed }) => [
                  styles.suggestion,
                  { borderColor: c.line, backgroundColor: pressed ? c.surface : c.background },
                ]}>
                <Text style={{ color: c.text, fontSize: 15 }}>{suggestion}</Text>
              </Pressable>
            ))}
          </View>
        </ScrollView>
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
                <View style={[styles.userBubble, { backgroundColor: c.surfaceStrong }]}>
                  <Text selectable style={[styles.userText, { color: c.text }]}>
                    {item.text}
                  </Text>
                </View>
              </Pressable>
            ) : (
              <View style={styles.assistant}>
                {item.pending && item.text.length === 0 ? (
                  <ActivityIndicator color={c.brand} style={styles.typing} />
                ) : (
                  <Markdown text={item.text} />
                )}
                {!item.pending && (
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel={copiedKey === item.key ? t.copied : t.copy}
                    onPress={() => copy(item)}
                    hitSlop={10}
                    style={styles.action}>
                    <Icon name={copiedKey === item.key ? 'check' : 'copy'} color={c.faint} size={17} />
                  </Pressable>
                )}
              </View>
            )
          }
        />
      )}

      {sendError && (
        <View style={styles.sendError}>
          <Notice tone="error">{sendError}</Notice>
        </View>
      )}

      <View style={[styles.composerWrap, { paddingBottom: Math.max(insets.bottom, 10) }]}>
        <View style={[styles.composer, { backgroundColor: c.surface, borderColor: c.line }]}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            placeholder={t.messagePlaceholder}
            placeholderTextColor={c.faint}
            multiline
            style={[styles.input, { color: c.text }]}
          />
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={streaming ? t.stop : t.send}
            onPress={streaming ? () => abortRef.current?.abort() : () => send()}
            disabled={!streaming && !canSend}
            style={({ pressed }) => [
              styles.sendButton,
              {
                backgroundColor: streaming || canSend ? c.text : c.surfaceStrong,
                opacity: pressed ? 0.8 : 1,
              },
            ]}>
            <Icon
              name={streaming ? 'stop' : 'send'}
              color={streaming || canSend ? c.background : c.faint}
              size={18}
            />
          </Pressable>
        </View>
        <Text style={[styles.disclaimer, { color: c.faint }]}>{t.disclaimer}</Text>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  errorBox: { flex: 1, padding: 16, gap: 10 },
  welcome: { flexGrow: 1, justifyContent: 'center', alignItems: 'center', padding: 24, gap: 20 },
  mark: { width: 56, height: 56 },
  greeting: { fontSize: 24, fontWeight: '600', textAlign: 'center' },
  suggestions: { width: '100%', maxWidth: 520, gap: 10 },
  suggestion: { borderWidth: 1, borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14 },
  messages: { padding: 16, gap: 22, maxWidth: 760, width: '100%', alignSelf: 'center' },
  userRow: { alignItems: 'flex-end' },
  userBubble: { maxWidth: '85%', borderRadius: 20, paddingHorizontal: 16, paddingVertical: 10 },
  userText: { fontSize: 16, lineHeight: 23 },
  assistant: { gap: 8 },
  typing: { alignSelf: 'flex-start' },
  action: { alignSelf: 'flex-start', paddingVertical: 2 },
  sendError: { paddingHorizontal: 16, paddingBottom: 8 },
  composerWrap: { paddingHorizontal: 12, paddingTop: 6, gap: 6 },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    borderWidth: 1,
    borderRadius: 26,
    paddingLeft: 16,
    paddingRight: 6,
    paddingVertical: 6,
    maxWidth: 760,
    width: '100%',
    alignSelf: 'center',
  },
  input: {
    flex: 1,
    minHeight: 40,
    maxHeight: 160,
    fontSize: 16,
    paddingTop: 10,
    paddingBottom: 10,
  },
  sendButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
  },
  disclaimer: { fontSize: 11, textAlign: 'center' },
});
