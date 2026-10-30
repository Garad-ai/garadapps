import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import * as api from './api';

type ConversationsValue = {
  items: api.Conversation[] | null;
  error: unknown;
  refresh: () => Promise<void>;
  remove: (id: number) => Promise<void>;
  setTitle: (id: number, title: string) => void;
};

const ConversationsContext = createContext<ConversationsValue | null>(null);

/** Conversation history shared by the drawer and the chat screen. */
export function ConversationsProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<api.Conversation[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  const refresh = useCallback(async () => {
    try {
      setItems(await api.getConversations());
      setError(null);
    } catch (e) {
      setError(e);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const remove = useCallback(async (id: number) => {
    await api.deleteConversation(id);
    setItems((current) => current?.filter((item) => item.id !== id) ?? null);
  }, []);

  const setTitle = useCallback((id: number, title: string) => {
    setItems((current) => current?.map((item) => (item.id === id ? { ...item, title } : item)) ?? null);
  }, []);

  const value = useMemo(
    () => ({ items, error, refresh, remove, setTitle }),
    [items, error, refresh, remove, setTitle]
  );

  return <ConversationsContext.Provider value={value}>{children}</ConversationsContext.Provider>;
}

export function useConversations(): ConversationsValue {
  const value = useContext(ConversationsContext);
  if (!value) throw new Error('useConversations must be used inside ConversationsProvider');
  return value;
}
