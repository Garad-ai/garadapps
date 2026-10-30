import { useLocalSearchParams } from 'expo-router';

import { ChatView } from '@/components/ChatView';

/** Home: a fresh chat. `n` changes on "New chat" so the view starts over. */
export default function NewChatScreen() {
  const { n } = useLocalSearchParams<{ n?: string }>();
  return <ChatView key={n ?? 'new'} />;
}
