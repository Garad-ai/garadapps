import { DrawerContentComponentProps } from 'expo-router/drawer';
import { router, usePathname } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  SectionList,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon } from '@/components/Icon';
import { useAccount } from '@/lib/account';
import { Conversation, getConversations } from '@/lib/api';
import { useConversations } from '@/lib/conversations';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { serif, usePalette } from '@/lib/theme';

export function ConversationDrawer({ navigation }: DrawerContentComponentProps) {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const pathname = usePathname();
  const { items, error, refresh, remove, setPinned } = useConversations();
  const { account } = useAccount();

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Conversation[] | null>(null);

  useEffect(() => {
    const word = query.trim();
    if (!word) {
      setResults(null);
      return;
    }
    const timer = setTimeout(() => {
      getConversations(word)
        .then(setResults)
        .catch(() => setResults([]));
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  const sections = useMemo(() => {
    const list = results ?? items ?? [];
    return [
      { title: t.starred, data: list.filter((item) => item.is_pinned) },
      { title: t.recents, data: list.filter((item) => !item.is_pinned) },
    ].filter((section) => section.data.length > 0);
  }, [results, items, t]);

  const go = (href: Parameters<typeof router.navigate>[0]) => {
    router.navigate(href);
    navigation.closeDrawer();
  };

  const newChat = () => go({ pathname: '/', params: { n: Date.now() } });

  const showActions = (item: Conversation) => {
    Alert.alert(item.title, undefined, [
      {
        text: item.is_pinned ? t.unstar : t.star,
        onPress: () => setPinned(item.id, !item.is_pinned).catch((e) => Alert.alert(errorMessage(e, t))),
      },
      {
        text: t.delete,
        style: 'destructive',
        onPress: () =>
          Alert.alert(t.deleteChatConfirm, item.title, [
            { text: t.cancel, style: 'cancel' },
            {
              text: t.delete,
              style: 'destructive',
              onPress: async () => {
                try {
                  await remove(item.id);
                  if (pathname === `/c/${item.id}`) newChat();
                } catch (e) {
                  Alert.alert(errorMessage(e, t));
                }
              },
            },
          ]),
      },
      { text: t.cancel, style: 'cancel' },
    ]);
  };

  const name = account?.user.name || account?.user.givenName || '';

  return (
    <View style={[styles.container, { backgroundColor: c.surface, paddingTop: insets.top + 12 }]}>
      <Text style={[styles.brand, { color: c.text }]}>Garad</Text>

      <Pressable
        accessibilityRole="button"
        onPress={newChat}
        style={({ pressed }) => [styles.newChat, { opacity: pressed ? 0.7 : 1 }]}>
        <View style={[styles.newChatIcon, { backgroundColor: c.brand }]}>
          <Text style={styles.plus}>+</Text>
        </View>
        <Text style={{ color: c.brand, fontSize: 16, fontWeight: '600' }}>{t.newChat}</Text>
      </Pressable>

      <View style={[styles.search, { backgroundColor: c.surfaceStrong }]}>
        <Icon name="search" color={c.faint} size={15} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder={t.searchChats}
          placeholderTextColor={c.faint}
          style={[styles.searchInput, { color: c.text }]}
          returnKeyType="search"
        />
      </View>

      <SectionList
        style={styles.flex}
        sections={sections}
        keyExtractor={(item) => String(item.id)}
        stickySectionHeadersEnabled={false}
        onRefresh={refresh}
        refreshing={false}
        ListEmptyComponent={
          items === null && !error ? (
            <ActivityIndicator color={c.brand} style={styles.loading} />
          ) : (
            <Text style={[styles.empty, { color: c.faint }]}>
              {error ? errorMessage(error, t) : t.noChats}
            </Text>
          )
        }
        renderSectionHeader={({ section }) => (
          <Text style={[styles.section, { color: c.faint }]}>{section.title}</Text>
        )}
        renderItem={({ item }) => {
          const active = pathname === `/c/${item.id}`;
          return (
            <Pressable
              onPress={() => go({ pathname: '/c/[id]', params: { id: String(item.id) } })}
              onLongPress={() => showActions(item)}
              style={({ pressed }) => [
                styles.item,
                { backgroundColor: active || pressed ? c.surfaceStrong : 'transparent' },
              ]}>
              <Text numberOfLines={1} style={[styles.itemText, { color: c.text }]}>
                {item.title}
              </Text>
            </Pressable>
          );
        }}
      />

      <Pressable
        accessibilityRole="button"
        onPress={() => go('/account')}
        style={({ pressed }) => [
          styles.profile,
          {
            borderTopColor: c.line,
            paddingBottom: Math.max(insets.bottom, 12),
            backgroundColor: pressed ? c.surfaceStrong : 'transparent',
          },
        ]}>
        <View style={[styles.avatar, { backgroundColor: c.text }]}>
          <Text style={[styles.avatarText, { color: c.background }]}>
            {(name || 'G').slice(0, 1).toUpperCase()}
          </Text>
        </View>
        <View style={styles.flex}>
          <Text numberOfLines={1} style={{ color: c.text, fontWeight: '600', fontSize: 15 }}>
            {name || t.account}
          </Text>
          {account?.subscription?.planId ? (
            <Text numberOfLines={1} style={{ color: c.faint, fontSize: 13 }}>
              {account.subscription.planId}
            </Text>
          ) : null}
        </View>
        <Icon name="chevron" color={c.faint} size={14} />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  flex: { flex: 1 },
  brand: { fontFamily: serif, fontSize: 26, paddingHorizontal: 18, marginBottom: 14 },
  newChat: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingVertical: 8 },
  newChatIcon: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
  plus: { color: '#fff', fontSize: 18, lineHeight: 20, fontWeight: '600' },
  search: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 12,
    paddingHorizontal: 12,
    height: 40,
    marginHorizontal: 12,
    marginTop: 10,
    marginBottom: 4,
  },
  searchInput: { flex: 1, fontSize: 15, paddingVertical: 0 },
  section: { fontSize: 12, fontWeight: '600', paddingHorizontal: 18, paddingTop: 18, paddingBottom: 6 },
  item: { marginHorizontal: 8, paddingHorizontal: 10, paddingVertical: 10, borderRadius: 10 },
  itemText: { fontSize: 15 },
  loading: { marginTop: 24 },
  empty: { paddingHorizontal: 18, paddingTop: 18, fontSize: 14, lineHeight: 20 },
  profile: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  avatar: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  avatarText: { fontSize: 15, fontWeight: '700' },
});
