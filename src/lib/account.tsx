import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import * as api from './api';

type AccountValue = {
  account: api.Account | null;
  error: unknown;
  refresh: () => Promise<void>;
};

const AccountContext = createContext<AccountValue | null>(null);

/** The signed-in user's account, plan and usage, from the same payload as the web Chat Pro. */
export function AccountProvider({ children }: { children: ReactNode }) {
  const [account, setAccount] = useState<api.Account | null>(null);
  const [error, setError] = useState<unknown>(null);

  const refresh = useCallback(async () => {
    try {
      setAccount(await api.getAccount());
      setError(null);
    } catch (e) {
      setError(e);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const value = useMemo(() => ({ account, error, refresh }), [account, error, refresh]);

  return <AccountContext.Provider value={value}>{children}</AccountContext.Provider>;
}

export function useAccount(): AccountValue {
  const value = useContext(AccountContext);
  if (!value) throw new Error('useAccount must be used inside AccountProvider');
  return value;
}
