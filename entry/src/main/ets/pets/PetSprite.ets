import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { LengthMetricsUnit } from '@kit.ArkUI'
import { number, object, string, strings } from '../dsh/DshWire'
import { PetPack, PetAnimation, petAnimation, petArtScale, petFrameAt, petIdleDelay, petIdleChoice } from './PetData'
import { petSheetBytes } from './PetStore'
@Component
export struct PetSprite {
 @Prop @Watch('refresh') pack:PetPack|undefined=undefined
 @Prop @Watch('refresh') state:string='idle'
 @Prop @Watch('refresh') tier:number=0
 @Prop @Watch('refresh') petSize:string='medium'
 @Prop @Watch('refresh') animations:boolean=true
 @Prop @Watch('react') reaction:string=''
 @Prop @Watch('react') reactionId:number=0
 @Prop @Watch('paint') flipped:boolean=false
 @Prop description:string=''
 // PixelMap source rectangles default to vp from API 18. Atlas cells are px.
 private canvas:CanvasRenderingContext2D=new CanvasRenderingContext2D(new RenderingContextSettings(false),LengthMetricsUnit.PX)
 private pixels:image.PixelMap|undefined=undefined
 private sheet:string=''
 private playing:PetAnimation|undefined=undefined
 private generation:number=0
 private started:number=0
 private reactionUntil:number=0
 private idleAt:number=0
 private variantUntil:number=0
 private timer:number=-1
 private ready:boolean=false
 private visible:boolean=true
 @State private spriteWidth:number=96
 @State private spriteHeight:number=96
 private artScale:number=1
 aboutToAppear():void{void this.refresh()}
 aboutToDisappear():void{this.generation++;this.stop();this.pixels?.release();this.pixels=undefined}
 private stop():void{if(this.timer!==-1){clearTimeout(this.timer);this.timer=-1}}
 private async refresh():Promise<void>{if(!this.pack)return;const dpr=this.getUIContext().vp2px(1);this.artScale=petArtScale(this.pack,this.petSize,dpr);this.spriteWidth=this.pack.width*this.artScale;this.spriteHeight=this.pack.height*this.artScale;this.reactionUntil=0;this.variantUntil=0;if(this.state!=='idle')this.idleAt=0;else if(!this.idleAt)this.idleAt=Date.now()+petIdleDelay(this.pack,Math.random());await this.choose(petAnimation(this.pack,this.state,this.tier))}
 private async choose(animation:PetAnimation):Promise<void>{try{const pack=this.pack;if(!pack)return;const same=this.playing?.name===animation.name;this.playing=animation;if(!same)this.started=Date.now();this.stop();const generation=++this.generation
  if(this.sheet!==pack.id+'|'+pack.directory+'|'+animation.sheet){this.pixels?.release();this.pixels=undefined;this.sheet='';const bytes=await petSheetBytes(getContext(this) as common.Context,pack,animation.sheet);const source=image.createImageSource(bytes.buffer);try{const pixels=await source.createPixelMap();if(generation!==this.generation){pixels.release();return}this.pixels=pixels;this.sheet=pack.id+'|'+pack.directory+'|'+animation.sheet}finally{source.release()}}
  if(generation===this.generation)this.tick()
 }catch{this.stop();this.pixels?.release();this.pixels=undefined;this.sheet='';this.paint()}}
 private react():void{if(!this.pack||!this.animations)return;const name=string(object(this.pack.raw['reactions'])[this.reaction]);const animation=this.pack.animations.find((a:PetAnimation)=>a.name===name);if(!animation)return;const timings=object(object(this.pack.raw['timings'])['playMs']);this.reactionUntil=Date.now()+number(timings[animation.name],animation.duration);void this.choose(animation)}
 private tick():void {this.stop();if(!this.visible)return;const now=Date.now();if(this.reactionUntil&&now>=this.reactionUntil){this.reactionUntil=0;void this.choose(petAnimation(this.pack!,this.state,this.tier));return}if(this.state==='idle'&&!this.reactionUntil&&this.animations){if(this.variantUntil&&now>=this.variantUntil){this.variantUntil=0;this.idleAt=now+petIdleDelay(this.pack,Math.random());void this.choose(petAnimation(this.pack!,'idle',0));return}if(!this.variantUntil&&this.idleAt&&now>=this.idleAt){this.idleAt=now+petIdleDelay(this.pack,Math.random());const idle=petIdleChoice(this.pack!,Math.random());if(idle){this.variantUntil=now+idle.ms;void this.choose(idle.animation);return}}}this.paint();if(this.animations&&this.playing){const frame=petFrameAt(this.playing,now-this.started);this.timer=setTimeout(()=>this.tick(),Math.max(16,Math.min(frame.ms,250)))} }
 private paint():void {if(!this.ready)return;const dpr=this.getUIContext().vp2px(1);this.canvas.clearRect(0,0,this.spriteWidth*dpr,this.spriteHeight*dpr);if(!this.pack||!this.playing||!this.pixels)return;const animation=this.playing,frame=petFrameAt(animation,Date.now()-this.started,this.animations),scale=this.artScale*dpr;this.canvas.imageSmoothingEnabled=!this.pack.pixelArt;this.canvas.save();if(this.flipped){this.canvas.translate(this.spriteWidth*dpr,0);this.canvas.scale(-1,1)}this.canvas.drawImage(this.pixels,(frame.i%animation.cols)*animation.frameW,Math.floor(frame.i/animation.cols)*animation.frameH,animation.frameW,animation.frameH,animation.box.x*scale,animation.box.y*scale,animation.box.w*scale,animation.box.h*scale);this.canvas.restore()}
 build(){Canvas(this.canvas).width(this.spriteWidth).height(this.spriteHeight).accessibilityText(this.description||this.pack?.name||'').onReady(()=>{this.ready=true;this.paint()}).onVisibleAreaChange([0,1],(visible:boolean)=>{this.visible=visible;if(visible)this.tick();else this.stop()})}
}
