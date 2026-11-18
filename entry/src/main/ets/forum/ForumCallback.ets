// Returns only a canonical Discourse RSA callback; never accepts an arbitrary page or auth origin.
export function forumAuthCallback(value: string): string | undefined {
  if (!value || value.length > 8192 || /[\x00-\x20\x7f\\]/.test(value)) return undefined;
  const match = /^dshgo:\/\/forum\/auth\?payload=([^&#]+)$/i.exec(value);
  if (!match) return undefined;
  let payload: string;
  try { payload = decodeURIComponent(match[1]).replace(/[\r\n]/g, ''); } catch { return undefined; }
  if (payload.length < 256 || payload.length > 4096 || payload.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(payload)) return undefined;
  return 'dshgo://forum/auth?payload=' + encodeURIComponent(payload);
}
