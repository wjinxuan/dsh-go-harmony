export function start(script: string, dataDir: string): number;
export function status(): number;
export function stop(): number;
export function probeShell(): Promise<string>;
