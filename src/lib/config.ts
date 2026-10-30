import Constants from 'expo-constants';

type Extra = {
  apiBaseUrl?: string;
  privacyUrl?: string;
  termsUrl?: string;
};

const extra = (Constants.expoConfig?.extra ?? {}) as Extra;

function trimSlash(value: string): string {
  return value.replace(/\/+$/, '');
}

/** Base URL of the Garad AI Laravel backend, e.g. https://garad.ai */
export const API_BASE_URL = trimSlash(
  process.env.EXPO_PUBLIC_API_BASE_URL || extra.apiBaseUrl || 'https://garad.ai'
);

export const PRIVACY_URL = extra.privacyUrl || `${API_BASE_URL}/privacy-policy`;
export const TERMS_URL = extra.termsUrl || `${API_BASE_URL}/terms`;

/** Turns a relative storage path from the API into an absolute URL. */
export function absoluteUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return path;
  return `${API_BASE_URL}/${path.replace(/^\/+/, '')}`;
}
