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
import { ModelSheet } from '@/components/ModelSheet';
import { Button, Notice } from '@/components/ui';
import { useAccount } from '@/lib/account';
import { createConversation, generateTitle, getMessages, messageText, streamChat } from '@/lib/api';
import { useConversations } from '@/lib/conversations';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { useModels } from '@/lib/models';
import { serif, usePalette } from '@/lib/theme';

type Bubble = { key: string; role: 'user' | 'assistant'; text: string; pending?: boolean };

/**
 * A conversation in the style of the Claude app. Without `conversationId` it starts with
 * a greeting and creates the conversation (in the web Chat Pro) on the first message.
 */
export function ChatView({ conversationId }: { conversationId?: number }) {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const conversations = useConversations();
  const { account } = useAccount();
  const { selected } = useModels();

  const [chatId, setChatId] = useState<number | undefined>(conversationId);
  const [bubbles, setBubbles] = useState<Bubble[] | null>(conversationId ? null : []);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [sendError, setSendError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [webSearch, setWebSearch] = useState(false);
  const [modelSheet, setModelSheet] = useState(false);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const listRef = useRef<FlatList<Bubble>>(null);
  const abortRef = useRef<AbortController | null>(null);

  const load = useCallback(async () => {
    if (!conversationId) return;
    try {
      const messages = await getMessages(conversationId);
      const next: Bubble[] = [];
      for (const message of messages) {
        // The first stored message is the assistant's canned greeting; the web skips it too.
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
    setStatus(null);
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
      const messageId = await streamChat(id, prompt, {
        model: selected?.id,
        webSearch,
        signal: controller.signal,
        onStatus: setStatus,
        onDelta: (delta) =>
          setBubbles((current) =>
            (current ?? []).map((bubble) =>
              bubble.key === replyKey ? { ...bubble, text: bubble.text + delta } : bubble
            )
          ),
      });
      if (isFirstMessage) {
        const conversation = id;
        await conversations.refresh();
        if (messageId) {
          generateTitle(messageId)
            .then((title) => title && conversations.setTitle(conversation, title))
            .catch(() => undefined);
        }
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
      setStatus(null);
      setStreaming(false);
    }
  };

  const copy = async (bubble: Bubble) => {
    await Clipboard.setStringAsync(bubble.text);
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setCopiedKey(bubble.key);
    setTimeout(() => setCopiedKey((key) => (key === bubble.key ? null : key)), 1500);
  };

  const hour = new Date().getHours();
  const greeting = hour < 12 ? t.greetingMorning : hour < 18 ? t.greetingAfternoon : t.greetingEvening;
  const firstName = account?.user.givenName || account?.user.name?.split(' ')[0];
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
          <View style={styles.greetingRow}>
            <Image
              source={require('../../assets/images/splash-icon.png')}
              style={styles.mark}
              contentFit="contain"
            />
            <Text style={[styles.greeting, { color: c.text }]}>
              {firstName ? `${greeting}, ${firstName}` : greeting}
            </Text>
          </View>
          <View style={styles.suggestions}>
            {t.suggestions.map((suggestion) => (
              <Pressable
                key={suggestion}
                accessibilityRole="button"
                onPress={() => send(suggestion)}
                style={({ pressed }) => [
                  styles.suggestion,
                  { borderColor: c.line, backgroundColor: pressed ? c.surface : c.card },
                ]}>
                <Text style={{ color: c.muted, fontSize: 14 }}>{suggestion}</Text>
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
                <View style={[styles.userBubble, { backgroundColor: c.userBubble }]}>
                  <Text selectable style={[styles.userText, { color: c.text }]}>
                    {item.text}
                  </Text>
                </View>
              </Pressable>
            ) : (
              <View style={styles.assistant}>
                {item.pending && item.text.length === 0 ? (
                  <View style={styles.thinking}>
                    <Image
                      source={require('../../assets/images/splash-icon.png')}
                      style={styles.thinkingMark}
                      contentFit="contain"
                    />
                    <Text style={[styles.thinkingText, { color: c.muted }]}>{status || t.thinking}</Text>
                  </View>
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
                    <Icon name={copiedKey === item.key ? 'check' : 'copy'} color={c.faint} size={16} />
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
        <View style={[styles.composer, { backgroundColor: c.card, borderColor: c.line }]}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            placeholder={t.messagePlaceholder}
            placeholderTextColor={c.faint}
            multiline
            style={[styles.input, { color: c.text }]}
          />
          <View style={styles.toolbar}>
            <Pressable
              accessibilityRole="switch"
              accessibilityLabel={t.webSearch}
              accessibilityState={{ checked: webSearch }}
              onPress={() => setWebSearch((value) => !value)}
              style={[
                styles.tool,
                {
                  borderColor: webSearch ? c.brand : c.line,
                  backgroundColor: webSearch ? c.brandSoft : 'transparent',
                },
              ]}>
              <Icon name="globe" color={webSearch ? c.brand : c.muted} size={16} />
              {webSearch && <Text style={{ color: c.brand, fontSize: 13, fontWeight: '500' }}>{t.webSearch}</Text>}
            </Pressable>
            <View style={styles.flex} />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={t.chooseModel}
              onPress={() => setModelSheet(true)}
              hitSlop={6}
              style={styles.modelChip}>
              <Text numberOfLines={1} style={[styles.modelName, { color: c.muted }]}>
                {selected?.displayName ?? 'Garad AI'}
              </Text>
              <Icon name="chevronDown" color={c.muted} size={12} />
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={streaming ? t.stop : t.send}
              onPress={streaming ? () => abortRef.current?.abort() : () => send()}
              disabled={!streaming && !canSend}
              style={({ pressed }) => [
                styles.sendButton,
                {
                  backgroundColor: streaming || canSend ? c.brand : c.surfaceStrong,
                  opacity: pressed ? 0.85 : 1,
                },
              ]}>
              <Icon
                name={streaming ? 'stop' : 'send'}
                color={streaming || canSend ? c.brandText : c.faint}
                size={16}
              />
            </Pressable>
          </View>
        </View>
      </View>

      <ModelSheet visible={modelSheet} onClose={() => setModelSheet(false)} />
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  errorBox: { flex: 1, padding: 16, gap: 10 },
  welcome: { flexGrow: 1, justifyContent: 'center', padding: 24, gap: 28 },
  greetingRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 12 },
  mark: { width: 34, height: 34 },
  greeting: { fontFamily: serif, fontSize: 30, lineHeight: 38, textAlign: 'center', flexShrink: 1 },
  suggestions: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 8 },
  suggestion: { borderWidth: 1, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 9 },
  messages: { padding: 18, gap: 24, maxWidth: 760, width: '100%', alignSelf: 'center' },
  userRow: { alignItems: 'flex-end' },
  userBubble: { maxWidth: '85%', borderRadius: 18, paddingHorizontal: 15, paddingVertical: 10 },
  userText: { fontSize: 16, lineHeight: 23 },
  assistant: { gap: 10 },
  thinking: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  thinkingMark: { width: 22, height: 22 },
  thinkingText: { fontSize: 15, fontStyle: 'italic' },
  action: { alignSelf: 'flex-start', paddingVertical: 2 },
  sendError: { paddingHorizontal: 16, paddingBottom: 8 },
  composerWrap: { paddingHorizontal: 10, paddingTop: 6 },
  composer: {
    borderWidth: 1,
    borderRadius: 24,
    paddingHorizontal: 14,
    paddingTop: 10,
    paddingBottom: 10,
    gap: 6,
    maxWidth: 760,
    width: '100%',
    alignSelf: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  input: { minHeight: 44, maxHeight: 160, fontSize: 16, paddingTop: 6, paddingBottom: 6 },
  toolbar: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  tool: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderRadius: 999,
    height: 32,
    paddingHorizontal: 9,
  },
  modelChip: { flexDirection: 'row', alignItems: 'center', gap: 4, maxWidth: 170 },
  modelName: { fontSize: 14 },
  sendButton: {
    width: 34,
    height: 34,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
