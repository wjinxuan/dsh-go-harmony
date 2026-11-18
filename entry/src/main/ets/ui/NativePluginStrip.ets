import { DshClient } from '../dsh/DshClient'
import { object, string, WireObject } from '../dsh/DshWire'
import { loadPluginPlaces } from './NativePluginActions'
import { NativePluginConnection } from './NativePluginConnection'
import { pluginCaps, PluginPlace } from './NativePluginData'
import { NativePluginView } from './NativePluginView'
import { nativePluginLocale } from './NativePluginLocale'
import { ThemeColors, themeColors } from './DshTheme'
@Component
export struct NativePluginStrip {
  @StorageProp('dshLanguage') @Watch('load') language: string = 'system'
  @Prop colors: ThemeColors = themeColors()
  @Prop @Watch('scopeChanged') scope: WireObject = {}
  client: DshClient = new DshClient()
  @State private places: PluginPlace[] = []
  private generation: number = 0
  @State private ownerKey: string = ''
  aboutToAppear(): void { void this.load() }
  aboutToDisappear(): void { this.generation++ }
  private scopeChanged(): void { void this.load() }
  private async load(): Promise<void> {
    const ownerKey = String(this.client.connectionIdentity()) + '|' + JSON.stringify(this.scope) + '|' + nativePluginLocale(this.language)
    if (ownerKey === this.ownerKey) return
    this.ownerKey = ownerKey
    const generation = ++this.generation; const identity = this.client.connectionIdentity(); this.places = []
    try { const all = await loadPluginPlaces(this.client,nativePluginLocale(this.language)); if (generation === this.generation && identity === this.client.connectionIdentity()) this.places = all.filter((place: PluginPlace) => place.surface === 'composer.strip').slice(0,8) } catch {}
  }
  build() {
    Column({space:4}) { ForEach(this.places,(place:PluginPlace)=>{NativePluginStripItem({colors:this.colors,place:place,scope:this.scope,client:this.client})},(place:PluginPlace)=>this.ownerKey+'|'+place.pkg+'|'+place.id) }.width('100%')
  }
}
@Component
struct NativePluginStripItem {
  @StorageProp('dshLanguage') @Watch('load') language:string='system'
  @Prop colors:ThemeColors=themeColors()
  @Prop @Watch('load') place:PluginPlace={pkg:'',plugin:'',id:'',title:'',surface:'composer.strip',placement:[],effects:[],wants:[],live:false}
  @Prop @Watch('load') scope:WireObject={}
  client:DshClient=new DshClient()
  @State private view:WireObject={}
  @State private data:WireObject={}
  private stream?:NativePluginConnection
  private generation:number=0
  private loadedKey:string=''
  aboutToAppear():void { void this.load() }
  aboutToDisappear():void {this.generation++;this.stream?.close()}
  private async load():Promise<void> {
    const key=String(this.client.connectionIdentity())+'|'+this.place.pkg+'|'+this.place.id+'|'+JSON.stringify(this.scope)+'|'+nativePluginLocale(this.language)
    if(key===this.loadedKey)return
    this.loadedKey=key;this.view={};this.data={}
    const generation=++this.generation;const identity=this.client.connectionIdentity();this.stream?.close()
    try {
      const query=pluginCaps(nativePluginLocale(this.language));for(const key of Object.keys(this.scope))query[key]=this.scope[key]
      const value=object(await this.client.bridgeJson('GET','/dsh-go/v1/views/'+this.place.pkg.split('/').map(encodeURIComponent).join('/')+'/'+encodeURIComponent(this.place.id),query))
      if(generation!==this.generation||identity!==this.client.connectionIdentity())return
      if(value['pkg']!==undefined&&value['pkg']!==this.place.pkg||value['id']!==undefined&&value['id']!==this.place.id)return
      this.view=object(value['view']);this.data=object(value['data'])
      const stream=new NativePluginConnection(this.client,nativePluginLocale(this.language));this.stream=stream
      stream.onData=(data:WireObject)=>{if(generation===this.generation&&identity===this.client.connectionIdentity())this.data=data}
      stream.onChanged=()=>{if(generation===this.generation){this.loadedKey='';void this.load()}}
      stream.onError=()=>{if(generation===this.generation)this.view={}}
      if(this.place.live||value['live']===true)await stream.subscribe(this.place,this.scope,this.data,string(value['rev']))
    }catch{if(generation===this.generation)this.view={}}
  }
  build(){if(Object.keys(this.view).length)NativePluginView({colors:this.colors,view:this.view,data:this.data,budget:'strip',pkg:this.place.pkg,client:this.client})}
}
