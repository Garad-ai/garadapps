import Constants from 'expo-constants';
import { Platform } from 'react-native';

import { SITE_URL } from './config';

/** Settings managed in Garad admin › Settings › Mobile App (GET /api/mobile-app/config). */
export type AppConfig = {
  latestVersion: string | null;
  minimumVersion: string | null;
  update: { androidUrl: string | null; iosUrl: string | null; message: string | null };
  maintenance: { enabled: boolean; message: string | null };
  announcement: { message: string; url: string | null } | null;
  links: { id: string; label: string; url: string }[];
};

export const APP_VERSION = Constants.expoConfig?.version ?? '1.0.0';

/** Compares dotted versions numerically: -1, 0 or 1. */
export function compareVersions(a: string, b: string): number {
  const left = a.split('.').map((part) => parseInt(part, 10) || 0);
  const right = b.split('.').map((part) => parseInt(part, 10) || 0);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const diff = (left[i] ?? 0) - (right[i] ?? 0);
    if (diff !== 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

/** Loads the admin's app settings; returns null when offline or the site is unreachable. */
export async function fetchAppConfig(timeoutMs = 6000): Promise<AppConfig | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${SITE_URL}/api/mobile-app/config`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (!response.ok) return null;
    const data = (await response.json()) as Partial<AppConfig>;
    return {
      latestVersion: data.latestVersion ?? null,
      minimumVersion: data.minimumVersion ?? null,
      update: {
        androidUrl: data.update?.androidUrl ?? null,
        iosUrl: data.update?.iosUrl ?? null,
        message: data.update?.message ?? null,
      },
      maintenance: {
        enabled: data.maintenance?.enabled === true,
        message: data.maintenance?.message ?? null,
      },
      announcement: data.announcement?.message ? data.announcement : null,
      links: Array.isArray(data.links) ? data.links : [],
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Where to send the user to update on this platform, if the admin set it. */
export function updateUrl(config: AppConfig | null): string | null {
  if (!config) return null;
  return Platform.OS === 'ios' ? config.update.iosUrl : config.update.androidUrl;
}

export function updateStatus(config: AppConfig | null): 'required' | 'available' | 'none' {
  if (!config) return 'none';
  if (config.minimumVersion && compareVersions(APP_VERSION, config.minimumVersion) < 0) return 'required';
  if (config.latestVersion && compareVersions(APP_VERSION, config.latestVersion) < 0) return 'available';
  return 'none';
}
