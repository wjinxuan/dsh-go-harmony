export const common={};
export const deviceInfo={sdkApiVersion:26};
export const fixture={calls:[],eventId:12,network:true,navigationError:false};
export const call={async makeCall(number){fixture.calls.push(['dial',number])}};
export const calendarManager={EventType:{NORMAL:0},getCalendarManager(){return{async editEvent(event){fixture.calls.push(['calendar',event]);return fixture.eventId}}}};
export const systemShare={SharePreviewMode:{DEFAULT:0},SharedData:class{constructor(record){this.record=record}},ShareController:class{constructor(data){this.data=data}async show(context,options){fixture.calls.push(['share',this.data.record,options])}}};
export const settings={async openNetworkManagerSettings(){fixture.calls.push(['wifi']);return fixture.network},openNfcSettingsPage(){fixture.calls.push(['nfc'])},openMobileNetworkSettingsPage(){fixture.calls.push(['mobile_network'])},openDisplaySettingsPage(){fixture.calls.push(['display'])},openSoundSettingsPage(){fixture.calls.push(['sound'])}};
export const notificationManager={async openNotificationSettings(){fixture.calls.push(['notifications'])}};
export const context={async startAbilityByType(type,params,callback){fixture.calls.push([type,params]);if(fixture.navigationError)callback.onError(42,'fixture','refused');else callback.onResult({resultCode:0})},async startAbility(want){fixture.calls.push(['want',want])}};
