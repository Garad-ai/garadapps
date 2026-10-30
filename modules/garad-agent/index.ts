import { requireOptionalNativeModule } from 'expo';

/**
 * The Garad agent: an Android AccessibilityService that, in milestone 1, only reads the
 * app in front when asked (see docs/AGENT_PLAN.md). On iOS and the web the native module
 * does not exist, so everything reports "unsupported".
 */
export type ScreenElement = {
  id: number;
  role: string | null;
  text: string | null;
  description: string | null;
  viewId: string | null;
  clickable: boolean;
  editable: boolean;
  scrollable: boolean;
  checked: boolean | null;
  password: boolean;
  /** left, top, right, bottom in screen pixels */
  bounds: [number, number, number, number];
};

export type ScreenReadResult =
  | { available: true; package: string | null; elements: ScreenElement[]; truncated: boolean }
  | { available: false; reason: 'unsupported' | 'not_enabled' | 'no_window' }
  | { available: false; reason: 'blocked_app'; package: string | null };

type NativeGaradAgent = {
  isEnabled(): boolean;
  isConnected(): boolean;
  openSettings(): void;
  disable(): void;
  readScreen(delayMs: number | null): Promise<ScreenReadResult>;
};

const native = requireOptionalNativeModule<NativeGaradAgent>('GaradAgent');

/** True on builds that include the agent (Android only). */
export const isSupported = native != null;

/** The user has turned Garad on in the phone's Accessibility settings. */
export function isEnabled(): boolean {
  return native?.isEnabled() ?? false;
}

/** The service is on and running right now. */
export function isConnected(): boolean {
  return native?.isConnected() ?? false;
}

/** Opens the phone's Accessibility settings, where the user turns Garad on or off. */
export function openSettings(): void {
  native?.openSettings();
}

/** Turns the agent off straight away. Turning it on always goes through the settings screen. */
export function disable(): void {
  native?.disable();
}

/**
 * Reads the app in front. `delayMs` (up to 30 s) waits natively first, so the user can
 * switch to another app; JS timers would pause while Garad is in the background.
 */
export async function readScreen(delayMs = 0): Promise<ScreenReadResult> {
  if (!native) return { available: false, reason: 'unsupported' };
  return native.readScreen(delayMs);
}
