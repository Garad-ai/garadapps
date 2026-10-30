import { requireOptionalNativeModule } from 'expo';

/**
 * The Garad agent: an Android AccessibilityService that reads the app in front and acts
 * on it when Garad Voice asks (see docs/AGENT_PLAN.md). On iOS and the web the native module
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
  perform(name: string, args: Record<string, unknown>): Promise<AgentResult>;
  evaluateInPage(script: string): void;
  isNotificationAccessEnabled(): boolean;
  openNotificationSettings(): void;
  getAnnounceAloud(): boolean;
  setAnnounceAloud(value: boolean): void;
};

/** What a screen action tells Garad Voice; `screen` describes the screen after it. */
export type AgentResult = { ok: boolean; message: string; screen?: string; needs_confirmation?: boolean };

/**
 * Actions carried out natively (AgentController.kt): the screen through the accessibility
 * service, messages and calls through notification access, and Voice bookkeeping.
 */
export const SCREEN_ACTIONS = new Set([
  'read_screen',
  'tap',
  'type_text',
  'scroll',
  'phone_button',
  'confirm_action',
  'stop',
  'read_messages',
  'reply_to_message',
  'answer_call',
  'decline_call',
  'voice_session',
]);

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

/** Garad may read message and call notifications (a separate switch in the phone settings). */
export function isNotificationAccessEnabled(): boolean {
  return native?.isNotificationAccessEnabled() ?? false;
}

/** Opens the phone's notification access settings. */
export function openNotificationSettings(): void {
  native?.openNotificationSettings();
}

/** Read new messages and calls aloud while Garad Voice is closed (off by default). */
export function getAnnounceAloud(): boolean {
  return native?.getAnnounceAloud() ?? false;
}

export function setAnnounceAloud(value: boolean): void {
  native?.setAnnounceAloud(value);
}

/** Runs a screen action requested by Garad Voice. Safety rules are enforced natively. */
export async function perform(name: string, args: Record<string, unknown>): Promise<AgentResult> {
  if (!native) return { ok: false, message: 'Screen actions are only available in the Android app.' };
  return native.perform(name, args);
}

/**
 * Runs a script in the Garad web page. Unlike WebView.injectJavaScript this also works
 * while the app is in the background, when the agent is working in another app.
 */
export function evaluateInPage(script: string): boolean {
  if (!native) return false;
  native.evaluateInPage(script);
  return true;
}

/**
 * Reads the app in front. `delayMs` (up to 30 s) waits natively first, so the user can
 * switch to another app; JS timers would pause while Garad is in the background.
 */
export async function readScreen(delayMs = 0): Promise<ScreenReadResult> {
  if (!native) return { available: false, reason: 'unsupported' };
  return native.readScreen(delayMs);
}
