import { object, string, number } from '../dsh/DshWire'
export interface WallpaperPreferences { path: string; on: boolean; width: number; height: number; zoom: number; alignX: number; alignY: number; blur: number; lighten: number; dim: number }
export interface AdvancedPreferences {
  customColor: string; foldCompletedTurns: boolean; sidebarOpen: boolean; panelOpen: boolean; glass: boolean;
  hardwareEnterSends: boolean; visualReplies: boolean; language: string; wallpaper: WallpaperPreferences
}
function clamp(value: number, min: number, max: number): number { return Math.max(min,Math.min(max,value)) }
export function advancedPreferences(value: Object | null | undefined = undefined): AdvancedPreferences {
  const row=object(value),paper=object(row['wallpaper']),color=string(row['customColor']),language=string(row['language'])
  return { customColor:/^#[\da-fA-F]{6}$/.test(color)?color.toUpperCase():'#5F7A55',foldCompletedTurns:row['foldCompletedTurns']!==false,
    sidebarOpen:row['sidebarOpen']!==false,panelOpen:row['panelOpen']!==false,glass:row['glass']!==false,hardwareEnterSends:row['hardwareEnterSends']===true,
    visualReplies:row['visualReplies']!==false,language:['zh','en','system'].includes(language)?language:'system',
    wallpaper:{path:string(paper['path']),on:paper['on']===true,width:number(paper['width'],0),height:number(paper['height'],0),zoom:clamp(number(paper['zoom'],1),1,5),alignX:clamp(number(paper['alignX'],0),-1,1),alignY:clamp(number(paper['alignY'],0),-1,1),blur:clamp(number(paper['blur'],.3),0,1),lighten:clamp(number(paper['lighten'],.2),0,1),dim:clamp(number(paper['dim'],.2),0,1)} }
}
export interface WallpaperFrame { width:number; height:number; x:number; y:number }
export function wallpaperFrame(paper: WallpaperPreferences, width: number, height: number): WallpaperFrame {
  if (paper.width<=0||paper.height<=0||width<=0||height<=0) return {width:0,height:0,x:0,y:0}
  const scale=Math.max(width/paper.width,height/paper.height)*clamp(paper.zoom,1,5),w=paper.width*scale,h=paper.height*scale
  return {width:w,height:h,x:(width-w)/2*(1+clamp(paper.alignX,-1,1)),y:(height-h)/2*(1+clamp(paper.alignY,-1,1))}
}
