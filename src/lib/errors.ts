import { ApiError } from './api';

type ErrorStrings = { networkError: string; genericError: string };

/** Returns a user-facing message for an error thrown by the API layer. */
export function errorMessage(error: unknown, t: ErrorStrings): string {
  if (error instanceof ApiError) {
    if (error.type === 'network') return t.networkError;
    if (error.message) return error.message;
  }
  return t.genericError;
}
