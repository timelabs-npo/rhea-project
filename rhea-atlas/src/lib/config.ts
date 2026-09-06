/**
 * Environment-aware API configuration for Orion Atlas.
 * Set NEXT_PUBLIC_RHEA_API and NEXT_PUBLIC_TRIBUNAL_API in your deployment
 * environment (Vercel env vars, .env.local, etc.) to point at the real backend.
 *
 * If undefined, the UI runs in offline/demo-only mode and no network requests
 * to the backend are made.
 */

const _rawApi = process.env.NEXT_PUBLIC_RHEA_API;
function _isValidUrl(s: string | undefined): s is string {
  if (!s) return false;
  try { new URL(s); return true; } catch { return false; }
}
export const API_BASE: string = _isValidUrl(_rawApi) ? _rawApi : '';
export const IS_API_CONFIGURED: boolean = API_BASE.length > 0;
export const TRIBUNAL_API: string =
  (process.env.NEXT_PUBLIC_TRIBUNAL_API ?? (IS_API_CONFIGURED ? `${API_BASE}/api` : ''));
export const IS_PRODUCTION: boolean = process.env.NODE_ENV === 'production';
