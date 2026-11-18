import { WireObject } from '../../dsh/DshWire';

export const PROVIDER_SETTINGS_NAMESPACE: string = 'llm-pi-ai';

export function providerEndpointValid(address: string): boolean {
  return /^https?:\/\/[^\s/?#@]+(?:\/[^\s?#]*)?$/i.test(address);
}

export function providerRouteValid(route: string): boolean {
  return /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(route);
}

export function providerModelIds(text: string): string[] {
  const ids: Set<string> = new Set();
  for (const line of text.split('\n')) {
    const id = line.trim();
    if (id) {
      ids.add(id);
    }
  }
  return Array.from(ids);
}

export function providerDiscoveryArgs(address: string, api: string, key: string,
  savedRoute?: string, savedAddress?: string, savedApi?: string): WireObject {
  const request: WireObject = {};
  request['baseURL'] = address;
  request['api'] = api;
  if (!key && savedRoute && savedAddress === address && savedApi === api) {
    request['provider'] = savedRoute;
  } else {
    if (key) {
      request['apiKey'] = key;
    }
  }
  const args: WireObject = {};
  args['settingsNs'] = PROVIDER_SETTINGS_NAMESPACE;
  args['request'] = request;
  return args;
}
