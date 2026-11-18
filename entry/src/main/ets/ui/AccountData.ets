import { object, string, WireObject } from '../dsh/DshWire';

export interface AccountClientMetadata {
  version: string;
  locale: string;
  timezoneOffsetSeconds: number;
}

export interface AccountProfile {
  name: string;
  contact: string;
}

export interface AccountOverview {
  status: 'loading' | 'signed-out' | 'credential-stored' | 'unsupported' | 'error';
  profile?: AccountProfile;
  profileFailed?: boolean;
  recharge?: string[];
  bonus?: string[];
  balanceFailed?: boolean;
  usageUrl?: string;
  topUpUrl?: string;
}

type AccountRequest = (method: string, args: WireObject, timeoutMs?: number) => Promise<Object | null | undefined>;

export interface AccountSignInAttempt {
  id: string;
  phase: 'initializing' | 'waiting-browser' | 'exchanging' | 'committing';
  authorizeUrl: string;
  expiresAt: number;
}

export type AccountSignInResult = 'signed-in' | 'cancelled' | 'expired' | 'failed' | 'unsafe-url';

export function accountCallbackOrigin(value: string): string {
  const match = /^http:\/\/127\.0\.0\.1:([1-9]\d{0,4})$/.exec(value);
  return match && Number(match[1]) <= 65535 && match[0] === value ? value : '';
}

export function accountAuthorizeUrl(value: string): string {
  // Only the production Platform authorization route can receive the browser handoff.
  return value.startsWith('https://platform.deepseek.com/dsh/authorize?') &&
    !/[\s\\#\x00-\x1f\x7f]/.test(value) ? value : '';
}

export function accountPlatformUrl(value: string): string {
  return /^https:\/\/platform\.deepseek\.com\/(?:usage|top_up)\/?$/.test(value) ? value : '';
}

function activeAccountAttempt(value: WireObject): AccountSignInAttempt | undefined {
  const id = string(value['id']);
  const phase = string(value['phase']);
  if (!id || (phase !== 'initializing' && phase !== 'waiting-browser' && phase !== 'exchanging' &&
    phase !== 'committing')) return undefined;
  const expires = value['expiresAt'];
  return { id: id, phase: phase, authorizeUrl: accountAuthorizeUrl(string(value['authorizeUrl'])),
    expiresAt: typeof expires === 'number' && Number.isFinite(expires) ? expires : 0 };
}

export async function runAccountSignIn(request: AccountRequest, client: AccountClientMetadata, origin: string,
  isCurrent: () => boolean, publish: (attempt: AccountSignInAttempt) => Promise<void>,
  wait: () => Promise<void>, canCancel: () => boolean = isCurrent): Promise<AccountSignInResult> {
  const callbackOrigin = accountCallbackOrigin(origin);
  if (!callbackOrigin || !isCurrent()) return 'cancelled';
  const args: WireObject = {};
  args['callbackOrigin'] = callbackOrigin;
  args['loginSource'] = 'web';
  args['client'] = client;
  let reply = await request('account/startSignIn', args);
  const deadline = Date.now() + 615000;
  let attemptId = '';
  let last: AccountSignInAttempt | undefined;
  while (true) {
    const attemptValue = object(object(reply)['attempt']);
    const attempt = activeAccountAttempt(attemptValue);
    attemptId = attemptId || string(attemptValue['id']);
    if (!isCurrent()) {
      if (canCancel()) {
        if (accountStatus(reply) === 'credential-stored') return 'signed-in';
        if (attempt && attempt.id === attemptId && await cancelAccountSignIn(request, attempt.id)) return 'signed-in';
      }
      return 'cancelled';
    }
    if (accountStatus(reply) === 'credential-stored') return 'signed-in';
    if (!attempt || attempt.id !== attemptId) {
      if (attemptValue['phase'] === 'expired') return 'expired';
      return attemptValue['phase'] === 'failed' || !attemptId ? 'failed' : 'cancelled';
    }
    if (Date.now() >= Math.min(deadline, attempt.expiresAt ? attempt.expiresAt + 15000 : deadline)) {
      return await cancelAccountSignIn(request, attempt.id) ? 'signed-in' : 'expired';
    }
    if (attempt.phase === 'waiting-browser' && !attempt.authorizeUrl) {
      await cancelAccountSignIn(request, attempt.id);
      return 'unsafe-url';
    }
    if (attempt.phase !== last?.phase || attempt.authorizeUrl !== last?.authorizeUrl) {
      last = attempt;
      await publish(attempt);
    }
    if (isCurrent()) await wait();
    if (!isCurrent()) {
      if (canCancel() && await cancelAccountSignIn(request, attempt.id)) return 'signed-in';
      return 'cancelled';
    }
    reply = await request('account/getState', {});
  }
}

async function cancelAccountSignIn(request: AccountRequest, id: string): Promise<boolean> {
  const args: WireObject = {};
  args['attemptId'] = id;
  const value = await request('account/cancelSignIn', args);
  return accountStatus(value) === 'credential-stored';
}

interface AccountDecimal {
  digits: bigint;
  scale: number;
}

function decimalWallet(value: string): AccountDecimal {
  if (value.length > 120) throw new Error('余额格式无效');
  const match = /^(-?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(value);
  if (!match || !(match[2] || match[3])) throw new Error('余额格式无效');
  const exponent = Number(match[4] || '0');
  if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 120) throw new Error('余额格式无效');
  const fraction = match[3] || '';
  const scale = fraction.length - exponent;
  const digits = BigInt(`${match[1]}${match[2]}${fraction}`);
  return { digits: scale < 0 ? digits * (BigInt(10) ** BigInt(-scale)) : digits, scale: Math.max(scale, 0) };
}

function sumWallets(first: AccountDecimal, second: AccountDecimal): AccountDecimal {
  const scale = Math.max(first.scale, second.scale);
  const digits = first.digits * (BigInt(10) ** BigInt(scale - first.scale)) +
    second.digits * (BigInt(10) ** BigInt(scale - second.scale));
  return { digits: digits, scale: scale };
}

function formatWalletAmount(value: AccountDecimal): string {
  const zero = BigInt(0);
  const hundred = BigInt(100);
  if (value.digits === zero) return '0.00';
  const negative = value.digits < zero;
  const digits = negative ? -value.digits : value.digits;
  let cents: bigint;
  if (value.scale <= 2) {
    cents = digits * (BigInt(10) ** BigInt(2 - value.scale));
  } else {
    const divisor = BigInt(10) ** BigInt(value.scale - 2);
    cents = digits / divisor;
    if (negative && (digits % divisor) * BigInt(2) >= divisor) cents += BigInt(1);
  }
  if (cents === zero && !negative) return '<0.01';
  if (cents === zero) cents = BigInt(1);
  const whole = (cents / hundred).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${negative ? '-' : ''}${whole}.${(cents % hundred).toString().padStart(2, '0')}`;
}

export function formatAccountWallets(value: Object | null | undefined): string[] {
  if (!Array.isArray(value)) throw new Error('余额格式无效');
  const totals: Map<string, AccountDecimal> = new Map();
  for (const item of value as Object[]) {
    const row = object(item);
    const currency = string(row['currency']);
    if (currency !== 'CNY' && currency !== 'USD') throw new Error('余额币种无效');
    const amount = decimalWallet(string(row['balance']));
    const total = totals.get(currency);
    totals.set(currency, total ? sumWallets(total, amount) : amount);
  }
  const lines: string[] = [];
  totals.forEach((amount: AccountDecimal, currency: string) => {
    lines.push(`${currency === 'CNY' ? '¥' : '$'}${formatWalletAmount(amount)}`);
  });
  return lines.length > 0 ? lines : ['¥0.00'];
}

function accountStatus(value: Object | null | undefined): 'signed-out' | 'credential-stored' {
  const status = string(object(value)['status']);
  if (status === 'signed-out' || status === 'credential-stored') return status;
  throw new Error('账号状态无效');
}

function accountText(value: Object | null | undefined): string {
  return string(value).replace(/[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]/g, '').trim().slice(0, 120);
}

export async function loadAccountOverview(request: AccountRequest, client: AccountClientMetadata,
  isCurrent: () => boolean, publish: (view: AccountOverview) => void): Promise<void> {
  let status: 'signed-out' | 'credential-stored';
  let links: WireObject = {};
  try {
    const state = await request('account/getState', {});
    status = accountStatus(state);
    links = object(object(state)['links']);
  } catch (error) {
    if (isCurrent()) {
      const unsupported = error instanceof Error && error.message === '主机请求失败（HTTP 404）';
      publish({ status: unsupported ? 'unsupported' : 'error' });
    }
    return;
  }
  if (!isCurrent()) return;
  publish({ status: status });
  if (status !== 'credential-stored') return;

  const overview: AccountOverview = { status: status };
  overview.usageUrl = accountPlatformUrl(string(links['usageUrl']));
  overview.topUpUrl = accountPlatformUrl(string(links['topUpUrl']));
  const args: WireObject = {};
  args['client'] = client;
  let changed = false;
  const refreshStatus = async (): Promise<void> => {
    if (changed || !isCurrent()) return;
    changed = true;
    publish({ status: 'loading' });
    try {
      const next = accountStatus(await request('account/getState', {}));
      if (!isCurrent()) return;
      if (next === 'signed-out') publish({ status: next });
      else publish({ status: next, profileFailed: true, balanceFailed: true });
    } catch {
      if (isCurrent()) publish({ status: 'error' });
    }
  };
  const update = (): void => {
    if (isCurrent() && !changed) publish({ status: overview.status, profile: overview.profile,
      profileFailed: overview.profileFailed, recharge: overview.recharge, bonus: overview.bonus,
      balanceFailed: overview.balanceFailed, usageUrl: overview.usageUrl, topUpUrl: overview.topUpUrl });
  };
  const profile = request('account/getProfile', args).then(async (reply: Object | null | undefined): Promise<void> => {
    if (reply === null) { await refreshStatus(); return; }
    const response = object(reply);
    if (response['status'] !== 'ready' || !response['value'] || typeof response['value'] !== 'object' ||
      Array.isArray(response['value'])) throw new Error('账号资料不可用');
    const value = object(response['value']);
    overview.profile = { name: accountText(value['name']), contact: accountText(value['contact']) };
  }).catch(() => { overview.profileFailed = true; }).then(update);
  const balance = request('account/getBalance', args, 35000).then(async (reply: Object | null | undefined): Promise<void> => {
    if (reply === null) { await refreshStatus(); return; }
    const response = object(reply);
    if (response['status'] !== 'ready') throw new Error('余额不可用');
    const recharge = formatAccountWallets(response['value']);
    const bonus = formatAccountWallets(response['bonusWallets']);
    overview.recharge = recharge;
    overview.bonus = bonus;
  }).catch(() => { overview.balanceFailed = true; }).then(update);
  await Promise.all([profile, balance]);
}
