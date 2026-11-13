export async function tryLockExclusive(fd) {
  const lock = globalThis.dshHarmonyTryLock;
  if (typeof lock !== 'function') throw new Error('Harmony session file lock is unavailable');
  if (!lock(fd)) {
    throw Object.assign(new Error('Session already has a writer'), { code: 'EAGAIN', syscall: 'flock' });
  }
}
