import { fetch as streamingFetch } from 'expo/fetch';

import { API_BASE_URL } from './config';
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

export type Profile = {
  id: number;
  name: string;
  surname: string | null;
  email: string;
  avatar: string | null;
};

export function getProfile(): Promise<Profile> {
  return request<Profile>('/api/auth/profile');
}

export function deleteAccount(): Promise<unknown> {
  return request('/api/auth/profile', { method: 'DELETE' });
}

export type Usage = {
  plan_name?: string;
  remaining_words?: number | string;
  remaining_images?: number | string;
  [key: string]: unknown;
};

export function getUsage(): Promise<Usage> {
  return request<Usage>('/api/app/usage-data');
}

// ---------------------------------------------------------------------------
// Chat

export type ChatTemplate = { id: number; name: string; slug: string };

export type Conversation = {
  id: number;
  title: string;
  updated_at: string;
};

export type ChatMessage = {
  id: number;
  input: string | null;
  output: string | null;
  response: string | null;
  created_at: string;
};

const DEFAULT_TEMPLATE_SLUG = 'ai-chat-bot';
let defaultTemplateId: number | null = null;

async function getDefaultTemplateId(): Promise<number> {
  if (defaultTemplateId !== null) return defaultTemplateId;
  const templates = await request<ChatTemplate[]>('/api/aichat/chat-templates');
  const preferred = templates.find((item) => item.slug === DEFAULT_TEMPLATE_SLUG) ?? templates[0];
  if (!preferred) throw new ApiError('No chat assistant is configured.', 404);
  defaultTemplateId = preferred.id;
  return preferred.id;
}

export function getConversations(): Promise<Conversation[]> {
  return request<Conversation[]>('/api/aichat/recent-chats');
}

export async function createConversation(): Promise<Conversation> {
  const categoryId = await getDefaultTemplateId();
  return request<Conversation>('/api/aichat/new-chat', {
    method: 'POST',
    body: { category_id: categoryId },
  });
}

export function renameConversation(id: number, title: string): Promise<unknown> {
  return request('/api/aichat/history', { method: 'PATCH', body: { conver_id: id, title } });
}

export function deleteConversation(id: number): Promise<unknown> {
  return request('/api/aichat/history', { method: 'DELETE', body: { conver_id: id } });
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
  if (message.response) return message.response;
  return (message.output ?? '').replace(/<br\s*\/?>/gi, '\n');
}

type StreamHandlers = {
  onDelta: (text: string) => void;
  signal?: AbortSignal;
};

/**
 * Sends a prompt and streams the assistant reply.
 *
 * The backend first stores the prompt (POST) and then streams the answer (GET).
 * The stream is newline-delimited text chunks where `<br/>` encodes a newline,
 * terminated by `data: [DONE]`; failures arrive as a line starting with `error:`.
 */
export async function sendMessage(
  conversationId: number,
  prompt: string,
  { onDelta, signal }: StreamHandlers
): Promise<void> {
  const { message_id } = await request<{ conver_id: number; message_id: number }>(
    '/api/aichat/chat-send',
    { method: 'POST', body: { conver_id: conversationId, prompt } }
  );

  const token = await tokenStore.get();
  const query = `conver_id=${conversationId}&message_id=${message_id}`;
  const response = await streamingFetch(`${API_BASE_URL}/api/aichat/chat-send?${query}`, {
    headers: {
      Accept: 'text/event-stream',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
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

  const handleLine = (line: string): boolean => {
    if (line.startsWith('data: [DONE]')) return true;
    if (line.startsWith('error:')) throw new ApiError(line.slice(6).trim(), 500, 'stream');
    if (line.length > 0) onDelta(line.replace(/<br\s*\/?>/gi, '\n'));
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
      if (handleLine(line)) {
        await reader.cancel();
        return;
      }
      newline = buffer.indexOf('\n');
    }
  }
  if (buffer.length > 0) handleLine(buffer);
}

// ---------------------------------------------------------------------------
// Images

export type GeneratedImage = {
  id: number;
  input: string | null;
  output: string | null;
  created_at?: string;
};

export async function generateImage(prompt: string): Promise<GeneratedImage[]> {
  const data = await request<{ status?: string; message?: string; images?: GeneratedImage[] }>(
    '/api/aiimage/generate-image',
    {
      method: 'POST',
      body: {
        description: prompt,
        size: '1024x1024',
        quality: 'medium',
        image_number_of_images: 1,
      },
    }
  );
  if (data.status === 'error') throw new ApiError(data.message ?? 'Image generation failed', 500);
  return data.images ?? [];
}

export function getRecentImages(): Promise<GeneratedImage[]> {
  return request<GeneratedImage[]>('/api/aiimage/recent-images');
}
