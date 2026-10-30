import { useLocalSearchParams, useNavigation } from 'expo-router';
import { useLayoutEffect } from 'react';

import { ChatView } from '@/components/ChatView';
import { useConversations } from '@/lib/conversations';

export default function ConversationScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const conversationId = Number(id);
  const navigation = useNavigation();
  const { items } = useConversations();
  const title = items?.find((item) => item.id === conversationId)?.title;

  useLayoutEffect(() => {
    if (title) navigation.setOptions({ title });
  }, [navigation, title]);

  return <ChatView key={conversationId} conversationId={conversationId} />;
}
