import { number, object, string } from '../dsh/DshWire'
import { common } from '@kit.AbilityKit'
import { ThemeColors, themeColors } from '../ui/DshTheme'
import { localizedSettingsText } from '../ui/SettingsLocale'
import { PetPack, PetPreferences, petPreferences, PetSessionSnapshot, PetMoodReducer, PetMood, petArtScale, petIdleDelay } from './PetData'
import { loadPet, loadPetPreferences, savePetPreferences } from './PetStore'
import { PetSprite } from './PetSprite'
@Component
export struct PetPerch {
 @StorageProp('dshLanguage') language:string='system'
 @StorageProp('dshPetRevision') @Watch('load') revision:number=0
 @Prop colors:ThemeColors=themeColors()
 @Prop @Watch('load') preferEnabled:boolean=true
 @Prop @Watch('update') animations:boolean=true
 @Prop @Watch('update') idleBlocked:boolean=false
 @Prop @Watch('update') sessions:PetSessionSnapshot[]=[]
 @Prop @Watch('update') focusId:string=''
 onOpenSession:(hostKey:string,sessionId:string)=>void=()=>{}
 onOpenCompanion:()=>void=()=>{}
 onSettings:()=>void=()=>{}
 @State private prefs:PetPreferences=petPreferences()
 @State private pack:PetPack|undefined=undefined
 @State private mood:PetMood={state:'idle',tier:0,targetId:'',targetHost:''}
 @State private menu:boolean=false
 @State private reaction:string=''
 @State private reactionId:number=0
 @State private perchPosition:number=0.25
 @State private perchWidth:number=320
 @State private walking:boolean=false
 @State private walkRight:boolean=false
 private walkTimer:number=-1
 private roamAt:number=0
 private roamed:boolean=false
 private dragging:boolean=false
 private reactionAt:number=0
 private reducer:PetMoodReducer=new PetMoodReducer()
 private timer:number=-1
 private generation:number=0
 private dragStart:number=0
 private t(value:string):string{return localizedSettingsText(value,this.language)}
 aboutToAppear():void{void this.load();this.timer=setInterval(()=>this.update(),1000)}
 aboutToDisappear():void{clearInterval(this.walkTimer);this.generation++;if(this.timer!==-1)clearInterval(this.timer)}
 private async load():Promise<void>{const generation=++this.generation;try{const prefs=await loadPetPreferences(getContext(this),this.preferEnabled);const pack=prefs.packId==='none'?undefined:await loadPet(getContext(this),prefs.packId);if(generation!==this.generation)return;this.prefs=prefs;this.perchPosition=prefs.position;this.pack=pack;this.reducer.configure(pack);this.roamAt=Date.now()+petIdleDelay(undefined,Math.random());this.roamed=false;this.update()}catch{if(generation===this.generation)this.pack=undefined}}
 private update():void{this.mood=this.reducer.update(this.sessions,this.focusId,this.prefs.quiet);if(this.prefs.hiddenUntil&&this.prefs.hiddenUntil<=Date.now()){this.prefs.hiddenUntil=0}if(!this.animations||this.idleBlocked||this.mood.state!=='idle'||this.mood.bubble||this.menu){clearInterval(this.walkTimer);this.walking=false;this.roamAt=Date.now()+petIdleDelay(undefined,Math.random())}else if(!this.walking&&Date.now()>=this.roamAt)this.roam()}
 private roam():void{const pack=this.pack;if(!pack||!this.animations||this.dragging||this.menu||this.idleBlocked||Date.now()<this.reactionAt)return;const from=this.perchPosition,home=this.prefs.position,to=this.roamed?home:Math.max(0,Math.min(1,from+(Math.random()<.5?-1:1)*(.08+Math.random()*.12)));const distance=Math.abs(to-from)*this.perchWidth;if(distance<4){this.roamAt=Date.now()+petIdleDelay(undefined,Math.random());return}const start=Date.now(),duration=distance/28*1000;this.walkRight=to>from;this.walking=true;clearInterval(this.walkTimer);this.walkTimer=setInterval(()=>{const elapsed=Math.min(1,(Date.now()-start)/duration);this.perchPosition=from+(to-from)*elapsed;if(elapsed===1){clearInterval(this.walkTimer);this.walking=false;this.roamed=Math.abs(to-home)>=.002;this.roamAt=Date.now()+petIdleDelay(undefined,Math.random())}},40)}
 private flipped():boolean{const face=string(object(this.pack?.raw['roam'])['faces']);return this.walking&&(face==='left'?this.walkRight:face==='right'?!this.walkRight:false)}
 private spriteHalf():number{return this.pack?this.pack.width*petArtScale(this.pack,this.prefs.size,this.getUIContext().vp2px(1))/2:0}
 private react(kind:string):void{clearInterval(this.walkTimer);this.walking=false;this.reactionAt=Date.now()+5000;this.roamAt=Date.now()+petIdleDelay(undefined,Math.random());this.reducer.touch();this.reaction=kind;this.reactionId++;this.update()}
 private openTarget():void{const bubble=this.mood.bubble;this.reducer.dismiss();this.update();if(bubble)this.onOpenSession(bubble.hostKey,bubble.sessionId);else if(this.mood.targetId)this.onOpenSession(this.mood.targetHost,this.mood.targetId)}
 private hide():void{this.prefs.hiddenUntil=Date.now()+3600000;this.menu=false;void savePetPreferences(getContext(this),this.prefs)}
 private offsetX():number {if(!this.pack)return 0;const scale=petArtScale(this.pack,this.prefs.size,this.getUIContext().vp2px(1));return Math.max(0,Math.min(this.perchWidth-this.pack.width*scale,this.perchPosition*this.perchWidth-this.pack.anchorX*scale))}
 private bubbleText():string{const bubble=this.mood.bubble;if(!bubble)return '';const label=bubble.kind==='done'?'完成了':bubble.kind==='failed'?'需要查看':'等你看看';return (bubble.count>1?bubble.count+' '+this.t('个会话'):bubble.title)+' · '+this.t(label)}
 build(){Stack({alignContent:Alignment.BottomStart}){
 if(this.pack&&this.prefs.packId!=='none'&&this.prefs.hiddenUntil<=Date.now()){
 Column({space:3}){if(this.mood.bubble)Text(this.bubbleText()).fontSize(12).fontColor(this.colors.text).padding({left:10,right:10,top:7,bottom:7}).backgroundColor(this.colors.surface).borderRadius(12).constraintSize({maxWidth:210}).onClick(()=>this.openTarget())
 PetSprite({pack:this.pack,state:this.walking?'roam':this.mood.state,flipped:this.flipped(),tier:this.mood.tier,petSize:this.prefs.size,animations:this.animations,reaction:this.reaction,reactionId:this.reactionId})
 .onClick((event:ClickEvent)=>{this.react(event.x<this.spriteHalf()?'tapLeft':'tapRight')})
 .gesture(GestureGroup(GestureMode.Exclusive,LongPressGesture().onAction(()=>{this.menu=true;this.reducer.touch()}),TapGesture({count:2}).onAction(()=>this.react('tickle'))))
 .parallelGesture(PanGesture({direction:PanDirection.Horizontal,distance:5}).onActionStart(()=>{this.dragging=true;this.dragStart=this.perchPosition;this.react('drag')}).onActionUpdate((event:GestureEvent)=>{this.perchPosition=Math.max(0,Math.min(1,this.dragStart+event.offsetX/this.perchWidth))}).onActionEnd(()=>{this.dragging=false;this.roamed=false;this.prefs.position=this.perchPosition;void savePetPreferences(getContext(this),this.prefs);this.react('tapRight')}))
 }.position({x:this.offsetX(),y:0})
 if(this.menu){Column({space:4}){Button(this.t('去看看')).onClick(()=>{this.menu=false;this.openTarget()});Button(this.t('伙伴小屋')).onClick(()=>{this.menu=false;this.onOpenCompanion()});Button(this.t('换一只')).onClick(()=>{this.menu=false;this.onSettings()});Button(this.t('宠物设置')).onClick(()=>{this.menu=false;this.onSettings()});Button(this.t('藏起来 1 小时')).onClick(()=>this.hide());Button(this.t('关闭')).onClick(()=>{this.menu=false})}.padding(8).backgroundColor(this.colors.surface).borderRadius(14).position({x:Math.min(this.offsetX(),Math.max(0,this.perchWidth-160)),y:-170})}
 }
 }.width('100%').height(this.pack?this.pack.height*petArtScale(this.pack,this.prefs.size,this.getUIContext().vp2px(1))+35:0).onAreaChange((_old:Area,area:Area)=>{this.perchWidth=Number(area.width)}).hitTestBehavior(HitTestMode.Transparent)}
}
