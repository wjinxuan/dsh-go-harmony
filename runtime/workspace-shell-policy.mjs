import { ShellExecutor } from '@deepseek-ai/dsh-shell';

// Permission presets consume the same sandbox policy as WorkspaceFileSystem.
// This process provides policy metadata without starting shell processes.
export default class WorkspaceShellPolicy extends ShellExecutor {
  static inject = ['sandboxPolicy'];

  constructor(ctx) {
    super(ctx);
    this.policy = ctx.sandboxPolicy;
  }

  get sandboxMode() {
    return this.policy.defaultMode;
  }

  resolve() {
    throw new Error('Shell execution is unavailable in Harmony DSH');
  }

  execute() {
    throw new Error('Shell execution is unavailable in Harmony DSH');
  }
}
