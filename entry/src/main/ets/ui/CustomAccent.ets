import type { ThemeColors } from './DshTheme'
interface Lch { l: number; c: number; h: number }
function clamp(value: number, min: number, max: number): number { return Math.max(min, Math.min(max, value)) }
function linear(value: number): number { return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4) }
function channels(value: string): number[] { return [1, 3, 5].map((index: number) => Number.parseInt(value.substring(index, index + 2), 16) / 255) }
function lch(color: string): Lch {
  const rgb = channels(color).map(linear), r = rgb[0], g = rgb[1], b = rgb[2]
  const lp = Math.cbrt(.4122214708*r+.5363325363*g+.0514459929*b), mp = Math.cbrt(.2119034982*r+.6806995451*g+.1073969566*b), sp = Math.cbrt(.0883024619*r+.2817188376*g+.6299787005*b)
  const a = 1.9779984951*lp-2.4285922050*mp+.4505937099*sp, bb = .0259040371*lp+.7827717662*mp-.8086757660*sp
  return { l: .2104542553*lp+.7936177850*mp-.0040720468*sp, c: Math.sqrt(a*a+bb*bb), h: (Math.atan2(bb,a)*180/Math.PI+360)%360 }
}
function rgb(l: number, c: number, h: number): number[] {
  const a = c*Math.cos(h*Math.PI/180), b = c*Math.sin(h*Math.PI/180)
  const lp = Math.pow(l+.3963377774*a+.2158037573*b,3), mp = Math.pow(l-.1055613458*a-.0638541728*b,3), sp = Math.pow(l-.0894841775*a-1.2914855480*b,3)
  return [4.0767416621*lp-3.3077115913*mp+.2309699292*sp,-1.2684380046*lp+2.6097574011*mp-.3413193965*sp,-.0041960863*lp-.7034186147*mp+1.7076147010*sp]
}
function inGamut(values: number[]): boolean { return values.every((value: number) => value >= -.0001 && value <= 1.0001) }
function tone(l: number, c: number, h: number): string {
  let values = rgb(clamp(l,0,1),c,h)
  if (!inGamut(values)) { let low = 0, high = c; for (let i=0;i<24;i++) { const mid = (low+high)/2; if (inGamut(rgb(l,mid,h))) low=mid; else high=mid } values=rgb(l,low,h) }
  return '#'+values.map((value: number) => { const v=clamp(value,0,1); return Math.round((v<=.0031308 ? 12.92*v : 1.055*Math.pow(v,1/2.4)-.055)*255).toString(16).padStart(2,'0') }).join('').toUpperCase()
}
export function contrastRatio(a: string,b: string): number {
  const aa=channels(a).map(linear),bb=channels(b).map(linear),la=.2126*aa[0]+.7152*aa[1]+.0722*aa[2],lb=.2126*bb[0]+.7152*bb[1]+.0722*bb[2]
  return (Math.max(la,lb)+.05)/(Math.min(la,lb)+.05)
}
function guarded(l: number,c: number,h: number,dark: boolean,surface: string,onAccent: string): string {
  let color=tone(l,c,h)
  if (contrastRatio(color,surface)>=3 && contrastRatio(onAccent,color)>=4.5) return color
  let pass=dark?1:0,fail=l
  for(let i=0;i<24;i++) { const mid=(pass+fail)/2; color=tone(mid,c,h); if(contrastRatio(color,surface)>=3 && contrastRatio(onAccent,color)>=4.5)pass=mid;else fail=mid }
  return tone(pass,c,h)
}
export function customAccentColors(base: ThemeColors, color: string, dark: boolean): ThemeColors {
  const pick=lch(/^#[0-9a-fA-F]{6}$/.test(color)?color:'#5F7A55'), c=Math.min(pick.c,.13),h=pick.h,k=.8*Math.min(1,c/.1255)
  const retint=(value:string):string=>{const o=lch(value);return tone(o.l,o.c*k,o.h+h-266)}
  const lightL=clamp(pick.l,.30,.60),onPrimary=dark?tone(.231,c*.39,h):'#FFFFFF'
  return { background:retint(base.background),backgroundTop:retint(base.backgroundTop),backgroundBottom:retint(base.backgroundBottom),surface:retint(base.surface),surfaceAlt:retint(base.surfaceAlt),
    text:retint(base.text),muted:retint(base.muted),hint:retint(base.hint),border:retint(base.border),codeSurface:retint(base.codeSurface),codeHeader:retint(base.codeHeader),codeBorder:retint(base.codeBorder),
    primary:guarded(dark?Math.min(.93,lightL+.234):lightL,c*(dark?.76:1),h,dark,retint(dark?'#343944':'#DFE4EE'),onPrimary),onPrimary:onPrimary,
    primaryContainer:tone(dark?.361:.93,c*(dark?.51:.26),h),onPrimaryContainer:tone(dark?.909:.33,c*(dark?.24:.70),h),bubble:tone(dark?.314:.918,c*.29,h),
    success:base.success,warning:base.warning,danger:base.danger }
}
