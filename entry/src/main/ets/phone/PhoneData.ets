import { array, object, string } from '../dsh/DshWire';
export interface PhonePolicy { confirmMode: string; denyPackages: string[]; confirmEveryWritePackages: string[]; localOcrEnabled: boolean; }
function packages(value: Object | null | undefined): string[] {
  const result: string[] = [];
  for (const item of array(value)) { const name = string(item); if (/^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+$/.test(name) && name.length <= 255 && !result.includes(name)) result.push(name); }
  return result.slice(0, 256);
}
export function phonePolicy(value: Object): PhonePolicy {
  const data = object(value);
  return { confirmMode: data['confirmMode'] === 'auto' ? 'auto' : 'ask', denyPackages: packages(data['denyPackages']),
    confirmEveryWritePackages: packages(data['confirmEveryWritePackages']), localOcrEnabled: data['localOcrEnabled'] !== false };
}
export function phoneCaptureSupported(device: string, sdk: number): boolean {
  return device === 'phone' ? sdk >= 21 : ['tablet', '2in1'].includes(device) && sdk >= 14;
}
export function phonePolicyRule(policy: PhonePolicy, bundle: string): string {
  if (policy.denyPackages.includes(bundle)) return 'deny';
  if (policy.confirmEveryWritePackages.includes(bundle)) return 'confirm';
  return 'default';
}
export function updatePhoneRule(policy: PhonePolicy, bundle: string, rule: string): PhonePolicy {
  if (!/^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+$/.test(bundle) || bundle.length > 255 || !['deny','confirm','default'].includes(rule)) throw new Error('请输入有效应用包名和规则');
  const deny = policy.denyPackages.filter((item: string) => item !== bundle), confirm = policy.confirmEveryWritePackages.filter((item: string) => item !== bundle);
  if (rule === 'deny') deny.push(bundle); if (rule === 'confirm') confirm.push(bundle);
  return { confirmMode: policy.confirmMode, denyPackages: deny, confirmEveryWritePackages: confirm, localOcrEnabled: policy.localOcrEnabled };
}
export interface PhoneCheck { stage: string; state: string; observed: boolean; detail: string; }
export function phoneChecks(device: string, sdk: number, width: number, height: number): PhoneCheck[] {
  return [
    { stage: 'device', state: 'pass', observed: true, detail: `${device} · API ${sdk}` },
    { stage: 'display', state: width > 0 && height > 0 ? 'pass' : 'fail', observed: width > 0 && height > 0, detail: `${width} × ${height}` },
    { stage: 'capture', state: phoneCaptureSupported(device,sdk) ? 'not_run' : 'unsupported', observed: false, detail: phoneCaptureSupported(device,sdk) ? '等待用户授权并实际截图' : '当前设备或系统版本不支持此截屏接口' },
    { stage: 'input', state: 'not_run', observed: false, detail: '需手动启用辅助服务，并以实际节点操作验证设备支持' },
    { stage: 'tree', state: 'not_run', observed: false, detail: '辅助接口已被标记废弃；当前设备能否调用须实际读取验证' },
    { stage: 'background', state: 'unsupported', observed: false, detail: 'Android Shizuku / Sui / root / ADB 通道不适用于 HarmonyOS 原生 HAP' }
  ];
}
