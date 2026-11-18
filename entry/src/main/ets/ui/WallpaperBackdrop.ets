import { fileUri } from '@kit.CoreFileKit'
import { WallpaperPreferences, advancedPreferences, wallpaperFrame } from './AdvancedPreferencesData'
import { ThemeColors, themeColors } from './DshTheme'
@Component
export struct WallpaperBackdrop {
  @Prop @Watch('paperChanged') paper: WallpaperPreferences = advancedPreferences().wallpaper
  @Prop colors: ThemeColors = themeColors()
  @Prop dark: boolean = false
  @State private frameWidth: number = 0
  @State private frameHeight: number = 0
  @State private broken: boolean = false
  private paperChanged(): void { this.broken = false }
  build() {
    Stack({alignContent:Alignment.TopStart}) {
      Column().width('100%').height('100%').linearGradient({angle:180,colors:[[this.colors.backgroundTop,0],[this.colors.backgroundBottom,1]]})
      if(this.paper.on && this.paper.path && !this.broken) {
        Image(fileUri.getUriFromPath(this.paper.path)).width(wallpaperFrame(this.paper,this.frameWidth,this.frameHeight).width)
          .height(wallpaperFrame(this.paper,this.frameWidth,this.frameHeight).height).objectFit(ImageFit.Fill)
          .position({x:wallpaperFrame(this.paper,this.frameWidth,this.frameHeight).x,y:wallpaperFrame(this.paper,this.frameWidth,this.frameHeight).y})
          .blur(this.paper.blur*36).onError(()=>this.broken=true)
        Column().width('100%').height('100%').backgroundColor(this.colors.background).opacity((this.dark?this.paper.dim:this.paper.lighten)*.8)
      }
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None)
      .onAreaChange((_old:Area,area:Area)=>{this.frameWidth=Number(area.width);this.frameHeight=Number(area.height)})
  }
}
