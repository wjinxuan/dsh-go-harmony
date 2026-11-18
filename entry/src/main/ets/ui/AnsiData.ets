// Ported from dsh-Go v1.0.15 ansi_text.dart (PiPilot-derived, MIT); see THIRD_PARTY_NOTICES.md.
export interface AnsiRun {
  text: string;
  foreground?: string;
  background?: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
}

const LIGHT: string[] = ['#1E232E', '#903C39', '#1B6C36', '#775300', '#2E5A9A', '#774382', '#006770', '#494D55',
  '#666970', '#A14B46', '#2D7B44', '#876114', '#3C69AA', '#865192', '#007781', '#2A2E36'];
const DARK: string[] = ['#7C8089', '#DE958E', '#81BB8D', '#C9A567', '#87ADE4', '#C499CE', '#5DBBC6', '#CED1D8',
  '#9A9EA7', '#F9AEA7', '#9AD5A5', '#E3BE80', '#A0C6FF', '#DEB2E9', '#78D5E0', '#F0F2F6'];
const ESCAPES = /\x1B\]([^\x07\x1B]*(?:\x07|\x1B\\|$))|\x1B\[([0-9;?]*)([A-Za-z])|\x1B\[[0-9;?]*$/g;

export function isDarkSurface(color: string): boolean {
  return parseInt(color.slice(1, 3), 16) * 0.299 + parseInt(color.slice(3, 5), 16) * 0.587 +
    parseInt(color.slice(5, 7), 16) * 0.114 < 128;
}

function rgb(red: number, green: number, blue: number): string {
  return '#' + [red, green, blue].map((value: number) => Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0')).join('');
}

function xtermColor(value: number, palette: string[]): string | undefined {
  if (!Number.isInteger(value) || value < 0 || value > 255) return undefined;
  if (value < 16) return palette[value];
  if (value < 232) {
    const cube = value - 16;
    const levels: number[] = [0, 95, 135, 175, 215, 255];
    return rgb(levels[Math.floor(cube / 36)], levels[Math.floor((cube % 36) / 6)], levels[cube % 6]);
  }
  const gray = 8 + (value - 232) * 10;
  return rgb(gray, gray, gray);
}

export function parseAnsi(text: string, dark: boolean): AnsiRun[] {
  const palette = dark ? DARK : LIGHT;
  const runs: AnsiRun[] = [];
  let foreground: string | undefined;
  let background: string | undefined;
  let bold = false;
  let italic = false;
  let underline = false;
  let offset = 0;
  ESCAPES.lastIndex = 0;
  let match = ESCAPES.exec(text);
  while (match) {
    if (match.index > offset) runs.push({ text: text.slice(offset, match.index), foreground, background, bold, italic, underline });
    offset = match.index + match[0].length;
    if (match[3] === 'm') {
      const params = (match[2] || '0').split(';').map((value: string) => Number(value) || 0);
      for (let index = 0; index < params.length; index++) {
        const code = params[index];
        if (code === 0) { foreground = undefined; background = undefined; bold = false; italic = false; underline = false; }
        else if (code === 1 || code === 22) bold = code === 1;
        else if (code === 3 || code === 23) italic = code === 3;
        else if (code === 4 || code === 24) underline = code === 4;
        else if (code === 39) foreground = undefined;
        else if (code === 49) background = undefined;
        else if (code >= 30 && code <= 37) foreground = palette[code - 30];
        else if (code >= 90 && code <= 97) foreground = palette[code - 82];
        else if (code >= 40 && code <= 47) background = '#2E' + palette[code - 40].slice(1);
        else if (code >= 100 && code <= 107) background = '#2E' + palette[code - 92].slice(1);
        else if (code === 38 || code === 48) {
          let color: string | undefined;
          if (params[index + 1] === 5) { color = xtermColor(params[index + 2], palette); index += 2; }
          else if (params[index + 1] === 2) {
            if (index + 4 < params.length) color = rgb(params[index + 2], params[index + 3], params[index + 4]);
            index = Math.min(index + 4, params.length);
          }
          if (color && code === 38) foreground = color;
          else if (color) background = '#2E' + color.slice(1);
        }
      }
    }
    match = ESCAPES.exec(text);
  }
  if (offset < text.length) runs.push({ text: text.slice(offset), foreground, background, bold, italic, underline });
  return runs;
}

export function stripAnsi(text: string): string {
  return text.replace(ESCAPES, '');
}
