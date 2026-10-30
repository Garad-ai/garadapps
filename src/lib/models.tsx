import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import * as api from './api';
import { modelStore } from './storage';

type ModelsValue = {
  models: api.Model[];
  selected: api.Model | null;
  select: (id: string) => void;
};

const ModelsContext = createContext<ModelsValue | null>(null);

/** The user's model catalogue (same as the web picker) and the model chosen for new messages. */
export function ModelsProvider({ children }: { children: ReactNode }) {
  const [models, setModels] = useState<api.Model[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([api.getModels(), modelStore.get()])
      .then(([list, stored]) => {
        setModels(list);
        const usable = list.filter((model) => !model.locked);
        const keep = usable.find((model) => model.id === stored);
        setSelectedId(keep?.id ?? usable[0]?.id ?? null);
      })
      .catch(() => undefined);
  }, []);

  const select = useCallback((id: string) => {
    setSelectedId(id);
    void modelStore.set(id);
  }, []);

  const value = useMemo(
    () => ({ models, selected: models.find((model) => model.id === selectedId) ?? null, select }),
    [models, selectedId, select]
  );

  return <ModelsContext.Provider value={value}>{children}</ModelsContext.Provider>;
}

export function useModels(): ModelsValue {
  const value = useContext(ModelsContext);
  if (!value) throw new Error('useModels must be used inside ModelsProvider');
  return value;
}
