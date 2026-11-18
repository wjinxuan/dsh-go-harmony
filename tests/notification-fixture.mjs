export const common={};export class DshClient{};
export const notices=[],agents=[];let allowed=true;export const allow=value=>allowed=value;
let publishHook;
export const holdPublish=fn=>publishHook=fn;
export const notificationManager={isNotificationEnabled:async()=>allowed,cancel:async()=>{},publish:async n=>{notices.push(n);if(publishHook)await publishHook(n)},SlotType:{SERVICE_INFORMATION:2},ContentType:{NOTIFICATION_CONTENT_BASIC_TEXT:0}};
export const bundleManager={BundleFlag:{GET_BUNDLE_INFO_DEFAULT:0},getBundleInfoForSelf:async()=>({name:'com.dshgo.harmony'})};
export const wantAgent={OperationType:{START_ABILITY:0},WantAgentFlags:{UPDATE_PRESENT_FLAG:0},getWantAgent:async value=>{agents.push(value);return value}};
const store=new Map();export const preferences={getPreferences:async()=>({getSync:(k,d)=>store.get(k)??d,putSync:(k,v)=>store.set(k,v),flush:async()=>{}})};
export const backgroundRequests=[],backgroundCancels=[],backgroundLogs=[];
let backgroundFailure,backgroundCancelFailure,backgroundGrantMs=180000;
export function resetBackground(){backgroundRequests.length=0;backgroundCancels.length=0;backgroundLogs.length=0;backgroundFailure=undefined;backgroundCancelFailure=undefined;backgroundGrantMs=180000;publishHook=undefined;allowed=true;}
export function rejectBackground(code){backgroundFailure=Object.assign(new Error('private fixture message must not be logged'),{code});}
export function rejectBackgroundCancel(code){backgroundCancelFailure=code===undefined?undefined:Object.assign(new Error('private cancel failure'),{code});}
export function grantBackground(ms){backgroundGrantMs=ms;}
export const backgroundTaskManager={requestSuspendDelay:(reason,expire)=>{if(backgroundFailure)throw backgroundFailure;const requestId=backgroundRequests.length+1;backgroundRequests.push({requestId,reason,expire});return{requestId,actualDelayTime:backgroundGrantMs}},cancelSuspendDelay:requestId=>{backgroundCancels.push(requestId);if(backgroundCancelFailure)throw backgroundCancelFailure}};
export const hilog={info:(...args)=>backgroundLogs.push(args),error:(...args)=>backgroundLogs.push(args)};
