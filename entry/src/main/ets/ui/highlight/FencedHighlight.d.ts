export interface HighlightRun {
  text: string;
  scopes: string[];
}
export function highlightLanguages(): string[];
export function normalizedLanguage(value: string): string;
export function codeChunks(code: string): string[];
export function highlightCode(code: string, label: string): HighlightRun[];
