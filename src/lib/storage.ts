import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

const TOKEN_KEY = 'garad.accessToken';
const LANGUAGE_KEY = 'garad.language';
const MODEL_KEY = 'garad.model';

// SecureStore is native-only; the web build (used for quick previews) falls back to localStorage.
async function getItem(key: string): Promise<string | null> {
  if (Platform.OS === 'web') {
    try {
      return globalThis.localStorage?.getItem(key) ?? null;
    } catch {
      return null;
    }
  }
  return SecureStore.getItemAsync(key);
}

async function setItem(key: string, value: string | null): Promise<void> {
  if (Platform.OS === 'web') {
    try {
      if (value === null) globalThis.localStorage?.removeItem(key);
      else globalThis.localStorage?.setItem(key, value);
    } catch {
      // Storage can be unavailable in private mode; the session simply won't persist.
    }
    return;
  }
  if (value === null) await SecureStore.deleteItemAsync(key);
  else await SecureStore.setItemAsync(key, value);
}

export const tokenStore = {
  get: () => getItem(TOKEN_KEY),
  set: (token: string | null) => setItem(TOKEN_KEY, token),
};

export const languageStore = {
  get: () => getItem(LANGUAGE_KEY),
  set: (language: string) => setItem(LANGUAGE_KEY, language),
};

export const modelStore = {
  get: () => getItem(MODEL_KEY),
  set: (model: string) => setItem(MODEL_KEY, model),
};
