import { fetch as streamingFetch } from 'expo/fetch';

import { API_BASE_URL, CHAT_WEBSITE_URL } from './config';
import { tokenStore } from './storage';

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public type?: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

let onUnauthorized: (() => void) | null = null;

/** Registers a callback fired when the backend rejects the stored token. */
export function setUnauthorizedHandler(handler: (() => void) | null) {
  onUnauthorized = handler;
}

function firstMessage(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return firstMessage(value[0]);
  if (typeof value === 'object') {
    for (const item of Object.values(value as Record<string, unknown>)) {
      const message = firstMessage(item);
      if (message) return message;
    }
  }
  return null;
}

function errorFromBody(body: unknown, status: number): ApiError {
  const record = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const message =
    firstMessage(record.error) ||
    firstMessage(record.message) ||
    firstMessage(record.errors) ||
    `Request failed (${status})`;
  return new ApiError(message, status, typeof record.type === 'string' ? record.type : undefined);
}

type RequestOptions = {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: Record<string, unknown>;
  auth?: boolean;
};

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, auth = true } = options;
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (body) headers['Content-Type'] = 'application/json';
  if (auth) {
    const token = await tokenStore.get();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError('network', 0, 'network');
  }

  const text = await response.text();
  let data: unknown = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }

  if (!response.ok) {
    if (response.status === 401 && auth) onUnauthorized?.();
    throw errorFromBody(data, response.status);
  }
  return data as T;
}

// ---------------------------------------------------------------------------
// Authentication

export type LoginInput = {
  email: string;
  password: string;
  otp?: string;
  oneTimePassword?: string;
  deviceName?: string;
};

export type LoginResult = { status: 'ok'; token: string } | { status: 'otp_sent'; message: string };

export async function login(input: LoginInput): Promise<LoginResult> {
  const data = await request<{ access_token?: string; type?: string; message?: string }>(
    '/api/auth/login',
    {
      method: 'POST',
      auth: false,
      body: {
        email: input.email,
        password: input.password,
        otp: input.otp || undefined,
        one_time_password: input.oneTimePassword || undefined,
        device_name: input.deviceName,
      },
    }
  );
  if (data.access_token) return { status: 'ok', token: data.access_token };
  return { status: 'otp_sent', message: data.message ?? '' };
}

export function register(input: {
  name: string;
  surname: string;
  email: string;
  password: string;
}): Promise<unknown> {
  return request('/api/auth/register', {
    method: 'POST',
    auth: false,
    body: { ...input, password_confirmation: input.password },
  });
}

export function forgotPassword(email: string): Promise<unknown> {
  return request('/api/auth/forgot-password', { method: 'POST', auth: false, body: { email } });
}

export function logout(): Promise<unknown> {
  return request('/api/auth/logout', { method: 'POST' });
}

// ---------------------------------------------------------------------------
// Account (the same payload the web Chat Pro shows)

export type Account = {
  user: { id: string; name: string; givenName: string; surname: string; email: string; avatarUrl?: string | null };
  subscription?: { planId?: string | null; status?: string } | null;
  usage?: { messages?: { used: number; limit: number } } | null;
};

export function getAccount(): Promise<Account> {
  return request<Account>('/api/v1/chat/account');
}

export function deleteAccount(): Promise<unknown> {
  return request('/api/auth/profile', { method: 'DELETE' });
}

// ---------------------------------------------------------------------------
// Models (the same catalogue as the web model picker, filtered by the user's plan)

export type Model = {
  id: string;
  displayName: string;
  description?: string | null;
  provider?: string | null;
  locked?: boolean;
  requiredPlan?: string | null;
};

export function getModels(): Promise<Model[]> {
  return request<Model[]>('/api/v1/chat/models');
}

// ---------------------------------------------------------------------------
// Conversations (shared with the web Chat Pro)

export type Conversation = {
  id: number;
  title: string;
  updated_at: string;
  is_pinned?: boolean;
};

export type ChatMessage = {
  id: number;
  input: string | null;
  output: string | null;
  response: string | null;
  created_at: string;
};

export async function getConversations(search?: string): Promise<Conversation[]> {
  const query = new URLSearchParams({
    website_url: CHAT_WEBSITE_URL,
    scope: 'sidebar_all',
    mode: 'chat',
    per_page: '50',
    ...(search ? { search } : {}),
  });
  const data = await request<{ chats?: Conversation[] }>(`/api/v1/chat/conversations?${query}`);
  return data.chats ?? [];
}

export async function createConversation(): Promise<number> {
  const data = await request<{ chat: { id: number } }>('/api/v1/chat/conversations', {
    method: 'POST',
    body: { react_chat: true, website_url: CHAT_WEBSITE_URL },
  });
  return data.chat.id;
}

export function renameConversation(id: number, title: string): Promise<unknown> {
  return request('/api/v1/chat/conversations/rename', {
    method: 'POST',
    body: { chat_id: `chat_${id}`, title },
  });
}

export function deleteConversation(id: number): Promise<unknown> {
  return request('/api/v1/chat/conversations/delete', {
    method: 'POST',
    body: { chat_id: `chat_${id}` },
  });
}

export function pinConversation(id: number, pinned: boolean): Promise<unknown> {
  return request('/api/v1/chat/conversations/pin', {
    method: 'POST',
    body: { chat_id: `chat_${id}`, pinned },
  });
}

/** Asks the backend to title a new conversation from its first exchange. */
export async function generateTitle(messageId: number): Promise<string | null> {
  const data = await request<{ changed?: boolean; new_title?: string }>(
    '/api/aichat/change-chat-title',
    { method: 'POST', body: { streamed_message_id: messageId } }
  );
  return data.changed && data.new_title ? data.new_title.replace(/^["']|["']$/g, '') : null;
}

export async function getMessages(conversationId: number): Promise<ChatMessage[]> {
  const page = await request<{ data?: ChatMessage[] } | ChatMessage[]>(
    `/api/aichat/chat/${conversationId}/messages?per_page=100`
  );
  const messages = Array.isArray(page) ? page : (page.data ?? []);
  // The API returns newest first.
  return [...messages].reverse();
}

/** Converts the HTML line breaks the backend stores in `output` back into plain newlines. */
export function messageText(message: Pick<ChatMessage, 'output' | 'response'>): string {
  const text = message.response || message.output || '';
  return text.replace(/<br\s*\/?>/gi, '\n');
}

export type StreamOptions = {
  model?: string;
  webSearch?: boolean;
  onDelta: (text: string) => void;
  onStatus?: (label: string | null) => void;
  signal?: AbortSignal;
};

function parseJson(data: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(data);
    return value && typeof value === 'object' ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/**
 * Sends a prompt through the web Chat Pro engine (generate-stream, template_type chatPro)
 * and streams the reply. Server-sent events: `data` carries text (with `<br/>` for
 * newlines), `message` the stored message id, `progress`/`tool_status` activity,
 * `error` a JSON error and `stop` the end. Returns the message id when known.
 */
export async function streamChat(
  chatId: number,
  prompt: string,
  { model, webSearch, onDelta, onStatus, signal }: StreamOptions
): Promise<number | null> {
  const token = await tokenStore.get();
  const response = await streamingFetch(`${API_BASE_URL}/api/v1/chat/stream`, {
    method: 'POST',
    headers: {
      Accept: 'text/event-stream',
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({
      template_type: 'chatPro',
      chat_id: chatId,
      prompt,
      raw_user_input: prompt,
      realtime: webSearch ? 1 : 0,
      website_url: CHAT_WEBSITE_URL,
      user_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      ...(model ? { chatbot_front_model: model } : {}),
    }),
    signal,
  });

  const isJson = (response.headers.get('content-type') ?? '').includes('application/json');
  if (!response.ok || !response.body || isJson) {
    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      // Non-JSON error body.
    }
    if (response.status === 401) onUnauthorized?.();
    throw errorFromBody(body, response.status);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let event = 'message';
  let data: string[] = [];
  let messageId: number | null = null;

  // Handles one complete server-sent event; returns true when the stream is finished.
  const dispatch = (): boolean => {
    const payload = data.join('\n');
    const name = event;
    event = 'message';
    data = [];
    if (name === 'stop' || payload === '[DONE]') return true;
    if (name === 'data' || name === 'delta') {
      const text = payload.replace(/<br\s*\/?>/gi, '\n');
      if (text) {
        onStatus?.(null);
        onDelta(text);
      }
    } else if (name === 'message') {
      const id = Number(parseJson(payload)?.id ?? payload);
      if (Number.isFinite(id) && id > 0) messageId = id;
    } else if (name === 'progress') {
      const message = parseJson(payload)?.message;
      onStatus?.(typeof message === 'string' ? message : payload || null);
    } else if (name === 'tool_status') {
      const label = parseJson(payload)?.label;
      onStatus?.(typeof label === 'string' ? label : null);
    } else if (name === 'error') {
      const object = parseJson(payload);
      const message = typeof object?.message === 'string' ? object.message : payload;
      throw new ApiError(message || 'Streaming error', 500, 'stream');
    }
    return false;
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let newline = buffer.indexOf('\n');
    while (newline !== -1) {
      const line = buffer.slice(0, newline).replace(/\r$/, '');
      buffer = buffer.slice(newline + 1);
      if (line === '') {
        if (data.length > 0 || event !== 'message') {
          if (dispatch()) {
            await reader.cancel();
            return messageId;
          }
        }
      } else if (line.startsWith('event:')) {
        event = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        data.push(line.slice(5).replace(/^ /, ''));
      }
      newline = buffer.indexOf('\n');
    }
  }
  if (data.length > 0) dispatch();
  return messageId;
}
