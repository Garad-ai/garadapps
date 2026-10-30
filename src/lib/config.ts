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

/** Base URL of the Garad AI backend (the Garad_ai Laravel app), e.g. https://garad.ai */
export const API_BASE_URL = trimSlash(
  process.env.EXPO_PUBLIC_API_BASE_URL || extra.apiBaseUrl || 'https://garad.ai'
);

export const PRIVACY_URL = extra.privacyUrl || `${API_BASE_URL}/privacy-policy`;
export const TERMS_URL = extra.termsUrl || `${API_BASE_URL}/terms`;

/** Identifies the app's conversations to the backend, matching the web Chat Pro. */
export const CHAT_WEBSITE_URL = 'chatpro';
