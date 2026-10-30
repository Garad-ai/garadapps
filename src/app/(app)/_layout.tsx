import { Stack } from 'expo-router';

import { usePalette } from '@/lib/theme';

export default function AppLayout() {
  const c = usePalette();
  return (
    <Stack
      screenOptions={{
        headerTintColor: c.text,
        headerStyle: { backgroundColor: c.background },
        headerShadowVisible: false,
        contentStyle: { backgroundColor: c.background },
      }}>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="chat/[id]" options={{ title: '' }} />
    </Stack>
  );
}
