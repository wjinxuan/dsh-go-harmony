export class ComposerDrafts {
  private drafts: Map<string, string> = new Map();
  read(sessionId: string): string { return this.drafts.get(sessionId) || ''; }
  write(sessionId: string, text: string): void {
    if (text) this.drafts.set(sessionId, text);
    else this.drafts.delete(sessionId);
  }
  append(sessionId: string, text: string): string {
    const previous = this.read(sessionId);
    const combined = previous ? `${previous}\n\n${text}` : text;
    this.write(sessionId, combined);
    return combined;
  }
  clear(): void { this.drafts.clear(); }
}
