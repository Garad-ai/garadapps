import { Tabs } from 'expo-router';
import { SymbolView } from 'expo-symbols';

import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

export default function TabsLayout() {
  const c = usePalette();
  const { t } = useI18n();

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: c.brand,
        tabBarInactiveTintColor: c.faint,
        tabBarStyle: { backgroundColor: c.background, borderTopColor: c.line },
        headerStyle: { backgroundColor: c.background },
        headerTintColor: c.text,
        headerShadowVisible: false,
      }}>
      <Tabs.Screen
        name="index"
        options={{
          title: t.chats,
          tabBarIcon: ({ color }) => (
            <SymbolView
              name={{ ios: 'bubble.left.and.bubble.right', android: 'forum', web: 'forum' }}
              tintColor={color}
              size={26}
            />
          ),
        }}
      />
      <Tabs.Screen
        name="images"
        options={{
          title: t.images,
          tabBarIcon: ({ color }) => (
            <SymbolView
              name={{ ios: 'photo.on.rectangle', android: 'image', web: 'image' }}
              tintColor={color}
              size={26}
            />
          ),
        }}
      />
      <Tabs.Screen
        name="account"
        options={{
          title: t.account,
          tabBarIcon: ({ color }) => (
            <SymbolView
              name={{ ios: 'person.crop.circle', android: 'account_circle', web: 'account_circle' }}
              tintColor={color}
              size={26}
            />
          ),
        }}
      />
    </Tabs>
  );
}
