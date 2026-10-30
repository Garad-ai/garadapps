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

import { Icon, IconName } from '@/components/Icon';
import { Conversation, getProfile, Profile, searchConversations } from '@/lib/api';
import { useConversations } from '@/lib/conversations';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

const DAY = 24 * 60 * 60 * 1000;

export function ConversationDrawer({ navigation }: DrawerContentComponentProps) {
  const c = usePalette();
  const { t } = useI18n();
  const insets = useSafeAreaInsets();
  const pathname = usePathname();
  const { items, error, refresh, remove } = useConversations();

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Conversation[] | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    getProfile()
      .then(setProfile)
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    const word = query.trim();
    if (!word) {
      setResults(null);
      return;
    }
    const timer = setTimeout(() => {
      searchConversations(word)
        .then(setResults)
        .catch(() => setResults([]));
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  const sections = useMemo(() => {
    const list = results ?? items ?? [];
    const startOfToday = new Date().setHours(0, 0, 0, 0);
    const groups: { title: string; data: Conversation[] }[] = [
      { title: t.today, data: [] },
      { title: t.yesterday, data: [] },
      { title: t.previous7, data: [] },
      { title: t.older, data: [] },
    ];
    for (const item of list) {
      const time = new Date(item.updated_at).getTime();
      const index =
        time >= startOfToday ? 0 : time >= startOfToday - DAY ? 1 : time >= startOfToday - 7 * DAY ? 2 : 3;
      groups[index].data.push(item);
    }
    return groups.filter((group) => group.data.length > 0);
  }, [results, items, t]);

  const go = (href: Parameters<typeof router.navigate>[0]) => {
    router.navigate(href);
    navigation.closeDrawer();
  };

  const confirmDelete = (item: Conversation) => {
    Alert.alert(t.deleteChatConfirm, item.title, [
      { text: t.cancel, style: 'cancel' },
      {
        text: t.delete,
        style: 'destructive',
        onPress: async () => {
          try {
            await remove(item.id);
            if (pathname === `/c/${item.id}`) go({ pathname: '/', params: { n: Date.now() } });
          } catch (e) {
            Alert.alert(errorMessage(e, t));
          }
        },
      },
    ]);
  };

  const fullName = [profile?.name, profile?.surname].filter(Boolean).join(' ');

  return (
    <View style={[styles.container, { backgroundColor: c.surface, paddingTop: insets.top + 8 }]}>
      <View style={styles.top}>
        <View style={[styles.search, { backgroundColor: c.surfaceStrong }]}>
          <Icon name="search" color={c.faint} size={16} />
          <TextInput
            value={query}
            onChangeText={setQuery}
            placeholder={t.search}
            placeholderTextColor={c.faint}
            style={[styles.searchInput, { color: c.text }]}
            returnKeyType="search"
          />
        </View>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={t.newChat}
          hitSlop={8}
          onPress={() => go({ pathname: '/', params: { n: Date.now() } })}>
          <Icon name="newChat" color={c.text} />
        </Pressable>
      </View>

      <NavRow icon="chat" label={t.newChat} onPress={() => go({ pathname: '/', params: { n: Date.now() } })} />
      <NavRow icon="images" label={t.images} active={pathname === '/images'} onPress={() => go('/images')} />

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
              onLongPress={() => confirmDelete(item)}
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
        <View style={[styles.avatar, { backgroundColor: c.brand }]}>
          <Text style={styles.avatarText}>{(profile?.name ?? 'G').slice(0, 1).toUpperCase()}</Text>
        </View>
        <View style={styles.flex}>
          <Text numberOfLines={1} style={{ color: c.text, fontWeight: '600', fontSize: 15 }}>
            {fullName || t.account}
          </Text>
          {profile?.email ? (
            <Text numberOfLines={1} style={{ color: c.faint, fontSize: 13 }}>
              {profile.email}
            </Text>
          ) : null}
        </View>
        <Icon name="chevron" color={c.faint} size={16} />
      </Pressable>
    </View>
  );
}

function NavRow({
  icon,
  label,
  onPress,
  active,
}: {
  icon: IconName;
  label: string;
  onPress: () => void;
  active?: boolean;
}) {
  const c = usePalette();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.nav,
        { backgroundColor: active || pressed ? c.surfaceStrong : 'transparent' },
      ]}>
      <Icon name={icon} color={c.text} size={20} />
      <Text style={{ color: c.text, fontSize: 15, fontWeight: '500' }}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  flex: { flex: 1 },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 12, marginBottom: 8 },
  search: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 12,
    paddingHorizontal: 12,
    height: 40,
  },
  searchInput: { flex: 1, fontSize: 15, paddingVertical: 0 },
  nav: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginHorizontal: 8,
    paddingHorizontal: 10,
    paddingVertical: 11,
    borderRadius: 10,
  },
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
  avatar: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: '#fff', fontSize: 16, fontWeight: '700' },
});
