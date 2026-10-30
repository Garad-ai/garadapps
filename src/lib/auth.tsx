import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import * as api from './api';
import { tokenStore } from './storage';

type AuthValue = {
  ready: boolean;
  signedIn: boolean;
  signIn: (token: string) => Promise<void>;
  signOut: (options?: { revoke?: boolean }) => Promise<void>;
};

const AuthContext = createContext<AuthValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    tokenStore.get().then((token) => {
      setSignedIn(Boolean(token));
      setReady(true);
    });
  }, []);

  const signIn = useCallback(async (token: string) => {
    await tokenStore.set(token);
    setSignedIn(true);
  }, []);

  const signOut = useCallback(async ({ revoke = true }: { revoke?: boolean } = {}) => {
    if (revoke) {
      try {
        await api.logout();
      } catch {
        // The local session is cleared even if the server is unreachable.
      }
    }
    await tokenStore.set(null);
    setSignedIn(false);
  }, []);

  useEffect(() => {
    api.setUnauthorizedHandler(() => void signOut({ revoke: false }));
    return () => api.setUnauthorizedHandler(null);
  }, [signOut]);

  const value = useMemo(
    () => ({ ready, signedIn, signIn, signOut }),
    [ready, signedIn, signIn, signOut]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth must be used inside AuthProvider');
  return value;
}
