import { router, useFocusEffect, useNavigation } from 'expo-router';
import { useCallback, useLayoutEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { Button, Notice } from '@/components/ui';
import { Conversation, createConversation, deleteConversation, getConversations } from '@/lib/api';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

export default function ConversationsScreen() {
  const c = usePalette();
  const { t, language } = useI18n();
  const navigation = useNavigation();

  const [items, setItems] = useState<Conversation[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    try {
      setItems(await getConversations());
      setError(null);
    } catch (e) {
      setError(errorMessage(e, t));
    }
  }, [t]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load])
  );

  const startChat = useCallback(async () => {
    setCreating(true);
    try {
      const chat = await createConversation();
      router.push({ pathname: '/chat/[id]', params: { id: String(chat.id), title: chat.title } });
    } catch (e) {
      Alert.alert(errorMessage(e, t));
    } finally {
      setCreating(false);
    }
  }, [t]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={t.newChat}
          onPress={startChat}
          disabled={creating}
          style={styles.headerButton}>
          {creating ? (
            <ActivityIndicator color={c.brand} />
          ) : (
            <Text style={{ color: c.brand, fontWeight: '700', fontSize: 16 }}>+ {t.newChat}</Text>
          )}
        </Pressable>
      ),
    });
  }, [navigation, startChat, creating, c, t]);

  const confirmDelete = (item: Conversation) => {
    Alert.alert(t.deleteChatConfirm, item.title, [
      { text: t.cancel, style: 'cancel' },
      {
        text: t.delete,
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteConversation(item.id);
            setItems((current) => current?.filter((entry) => entry.id !== item.id) ?? null);
          } catch (e) {
            Alert.alert(errorMessage(e, t));
          }
        },
      },
    ]);
  };

  const refresh = async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  };

  if (items === null && !error) {
    return (
      <View style={[styles.center, { backgroundColor: c.background }]}>
        <ActivityIndicator color={c.brand} />
      </View>
    );
  }

  const dateFormat = new Intl.DateTimeFormat(language === 'so' ? 'so-SO' : 'en-US', {
    month: 'short',
    day: 'numeric',
  });

  return (
    <FlatList
      style={{ backgroundColor: c.background }}
      contentContainerStyle={styles.list}
      data={items ?? []}
      keyExtractor={(item) => String(item.id)}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} />}
      ListHeaderComponent={
        error ? (
          <View style={styles.header}>
            <Notice tone="error">{error}</Notice>
            <Button title={t.retry} variant="secondary" onPress={load} />
          </View>
        ) : undefined
      }
      ListEmptyComponent={
        error ? undefined : (
          <View style={styles.empty}>
            <Text style={[styles.emptyText, { color: c.muted }]}>{t.noChats}</Text>
            <Button title={t.newChat} onPress={startChat} loading={creating} />
          </View>
        )
      }
      renderItem={({ item }) => (
        <Pressable
          onPress={() =>
            router.push({ pathname: '/chat/[id]', params: { id: String(item.id), title: item.title } })
          }
          onLongPress={() => confirmDelete(item)}
          style={({ pressed }) => [
            styles.row,
            { borderBottomColor: c.line, backgroundColor: pressed ? c.surface : c.background },
          ]}>
          <Text numberOfLines={1} style={[styles.title, { color: c.text }]}>
            {item.title}
          </Text>
          <Text style={{ color: c.faint }}>{dateFormat.format(new Date(item.updated_at))}</Text>
        </Pressable>
      )}
    />
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { flexGrow: 1 },
  header: { padding: 16, gap: 10 },
  headerButton: { paddingHorizontal: 16, paddingVertical: 6 },
  empty: { flex: 1, padding: 32, gap: 16, justifyContent: 'center' },
  emptyText: { textAlign: 'center', fontSize: 16, lineHeight: 22 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: { flex: 1, fontSize: 16, fontWeight: '500' },
});
