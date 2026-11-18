// A model task is the engine's committed session/turn, not one tool call.
export function phoneTaskFirstStart(started: string[], taskId: string): boolean {
  if (!taskId || started.includes(taskId)) return false;
  started.push(taskId);
  if (started.length > 128) started.shift();
  return true;
}
