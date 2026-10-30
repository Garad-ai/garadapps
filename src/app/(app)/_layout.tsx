import { router } from 'expo-router';
import { Drawer } from 'expo-router/drawer';
import { Pressable } from 'react-native';

import { ConversationDrawer } from '@/components/ConversationDrawer';
import { Icon } from '@/components/Icon';
import { AccountProvider } from '@/lib/account';
import { ConversationsProvider } from '@/lib/conversations';
import { useI18n } from '@/lib/i18n';
import { ModelsProvider } from '@/lib/models';
import { usePalette } from '@/lib/theme';

export default function AppLayout() {
  const c = usePalette();
  const { t } = useI18n();

  const newChatButton = () => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={t.newChat}
      hitSlop={10}
      onPress={() => router.navigate({ pathname: '/', params: { n: Date.now() } })}
      style={{ marginHorizontal: 16 }}>
      <Icon name="newChat" color={c.text} />
    </Pressable>
  );

  return (
    <AccountProvider>
      <ModelsProvider>
        <ConversationsProvider>
          <Drawer
            drawerContent={(props) => <ConversationDrawer {...props} />}
            screenOptions={{
              headerStyle: { backgroundColor: c.background },
              headerTintColor: c.text,
              headerShadowVisible: false,
              headerTitleAlign: 'center',
              headerTitleStyle: { fontSize: 16, fontWeight: '600' },
              drawerStyle: { backgroundColor: c.surface, width: 300 },
              sceneStyle: { backgroundColor: c.background },
              swipeEdgeWidth: 60,
            }}>
            <Drawer.Screen name="index" options={{ title: '', headerRight: newChatButton }} />
            <Drawer.Screen name="c/[id]" options={{ title: '', headerRight: newChatButton }} />
            <Drawer.Screen name="account" options={{ title: t.account }} />
          </Drawer>
        </ConversationsProvider>
      </ModelsProvider>
    </AccountProvider>
  );
}
