@Entry
@Component
struct CompanionFormCard {
 @LocalStorageProp('name') companionName:string='Companion'
 @LocalStorageProp('status') status:string=''
 @LocalStorageProp('line') line:string=''
 @LocalStorageProp('pearls') pearls:string=''
 @LocalStorageProp('picture') picture:string='idle'
 build(){Column({space:5}){Row(){Text(this.companionName).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#254650').layoutWeight(1).maxLines(1);Text(this.pearls).fontSize(9).fontColor('#438E9B')}.width('100%');Row({space:6}){Image(this.picture==='sleeping'?$r('app.media.companion_widget_sleeping'):this.picture==='happy'?$r('app.media.companion_widget_happy'):$r('app.media.companion_widget_idle')).width(68).height(68).objectFit(ImageFit.Contain);Column({space:5}){Text(this.status).fontSize(12).fontColor('#466D75').maxLines(2);if(this.line)Text(this.line).fontSize(12).fontColor('#254650').maxLines(3)}.alignItems(HorizontalAlign.Start).layoutWeight(1)}.layoutWeight(1).width('100%')}.padding(12).width('100%').height('100%').backgroundColor('#EAF7F6').borderRadius(20).onClick(()=>{postCardAction(this,{action:'router',abilityName:'EntryAbility',params:{'dsh.page':'companion'}})})}
}
