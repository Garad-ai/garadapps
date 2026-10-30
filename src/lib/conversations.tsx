import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import * as api from './api';

type ConversationsValue = {
  items: api.Conversation[] | null;
  error: unknown;
  refresh: () => Promise<void>;
  remove: (id: number) => Promise<void>;
  setPinned: (id: number, pinned: boolean) => Promise<void>;
  setTitle: (id: number, title: string) => void;
};

const ConversationsContext = createContext<ConversationsValue | null>(null);

/** Conversation history shared by the sidebar and the chat screen (same list as the web). */
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

  const setPinned = useCallback(async (id: number, pinned: boolean) => {
    await api.pinConversation(id, pinned);
    setItems(
      (current) => current?.map((item) => (item.id === id ? { ...item, is_pinned: pinned } : item)) ?? null
    );
  }, []);

  const setTitle = useCallback((id: number, title: string) => {
    setItems((current) => current?.map((item) => (item.id === id ? { ...item, title } : item)) ?? null);
  }, []);

  const value = useMemo(
    () => ({ items, error, refresh, remove, setPinned, setTitle }),
    [items, error, refresh, remove, setPinned, setTitle]
  );

  return <ConversationsContext.Provider value={value}>{children}</ConversationsContext.Provider>;
}

export function useConversations(): ConversationsValue {
  const value = useContext(ConversationsContext);
  if (!value) throw new Error('useConversations must be used inside ConversationsProvider');
  return value;
}
