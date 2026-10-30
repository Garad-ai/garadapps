import Constants from 'expo-constants';

type Extra = {
  siteUrl?: string;
  startPath?: string;
};

const extra = (Constants.expoConfig?.extra ?? {}) as Extra;

function trimSlash(value: string): string {
  return value.replace(/\/+$/, '');
}

/** The Garad AI website the app shows, e.g. https://garad.ai */
export const SITE_URL = trimSlash(
  process.env.EXPO_PUBLIC_SITE_URL || extra.siteUrl || 'https://garad.ai'
);

/** First page the app opens: the Chat Pro web app. */
export const START_URL = `${SITE_URL}${extra.startPath || '/chat'}`;

const siteHost = new URL(SITE_URL).hostname.replace(/^www\./, '');

/** True for garad.ai and its subdomains; everything else opens outside the app. */
export function isSiteUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return host === siteHost || host.endsWith(`.${siteHost}`);
  } catch {
    return false;
  }
}

/** Added to the browser user agent so the website can tell it is running inside the app. */
export const APP_USER_AGENT = `GaradApp/${Constants.expoConfig?.version ?? '1.0.0'}`;
