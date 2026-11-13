import { DshTodo } from '../dsh/DshWire';

export function todoSummary(todos: DshTodo[], running: boolean): string {
  const completed = todos.filter((item) => item.status === 'completed').length;
  const current = todos.find((item) => item.status === 'in_progress') || todos.find((item) => item.status !== 'completed');
  return `${completed}/${todos.length} · ${!current ? '全部完成' :
    (running && current.status === 'in_progress' ? '正在：' : '下一步：') + current.content}`;
}

export function goalHeadline(objective: string): string {
  return objective.split('\n').find((line: string) => !!line.trim())?.trim() || objective.trim();
}
