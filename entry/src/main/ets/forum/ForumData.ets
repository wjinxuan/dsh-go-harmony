import { array, object, string, number } from '../dsh/DshWire';
import type { WireObject } from '../dsh/DshWire';
export interface ForumCategory { id: number; name: string; slug: string; parent: number; permission: number; position: number; }
export interface ForumTopic { id: number; title: string; replies: number; views: number; likes: number; closed: boolean; pinned: boolean; categoryId: number; activity: string; excerpt: string; }
export interface ForumPost { id: number; topicId: number; number: number; username: string; name: string; markdown: string; likes: number; liked: boolean; canLike: boolean; canUnlike: boolean; bookmarked: boolean; bookmarkId: number; hidden: boolean; deleted: boolean; created: string; replyTo: number; images: string[]; }
export interface ForumNotification { id: number; type: number; read: boolean; topicId: number; postNumber: number; title: string; actor: string; }
export function forumText(value: Object | null | undefined): string {
  return string(value).replace(/<[^>]*>/g, '').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'");
}
export function forumCategories(value: Object): ForumCategory[] {
  return array(object(value)['categories']).map((item: Object): ForumCategory => { const row = object(item);
    return { id: number(row['id'],0), name: forumText(row['name']), slug: string(row['slug']), parent: number(row['parent_category_id'],0),
      permission: number(row['permission'],0), position: number(row['position'],0) };
  }).filter((item: ForumCategory) => item.id > 0).sort((a: ForumCategory,b: ForumCategory) => a.position-b.position);
}
export function forumTopic(value: Object): ForumTopic { const row=object(value);
  return {id:number(row['id'],0),title:forumText(row['title']||row['fancy_title']),replies:Math.max(0,number(row['posts_count'],1)-1),
    views:number(row['views'],0),likes:number(row['like_count'],0),closed:row['closed']===true,pinned:row['pinned']===true,
    categoryId:number(row['category_id'],0),activity:string(row['last_posted_at']||row['bumped_at']||row['created_at']),excerpt:forumText(row['excerpt'])};
}
export function forumTopics(value: Object): ForumTopic[] {return array(object(object(value)['topic_list'])['topics']).map(forumTopic).filter((item:ForumTopic)=>item.id>0);}
export function forumPosts(value: Object): ForumPost[] {
  const data=object(value), stream=object(data['post_stream']);
  const bookmarks=array(data['bookmarks']);
  return array(stream['posts']||data['posts']).map((item:Object):ForumPost=>{const row=object(item);
    const like=object(array(row['actions_summary']).find((item:Object)=>number(object(item)['id'],0)===2));
    const bookmark=object(bookmarks.find((item:Object)=>number(object(item)['bookmarkable_id'],0)===number(row['id'],0)&&object(item)['bookmarkable_type']==='Post'));
    return {id:number(row['id'],0),topicId:number(row['topic_id'],0),number:number(row['post_number'],1),username:string(row['username']),name:string(row['name']),
      markdown:string(row['native_markdown']),likes:number(like['count'],number(row['like_count'],0)),liked:like['acted']===true||row['current_user_used_main_reaction']===true,
      canLike:like['can_act']===true,canUnlike:like['can_undo']===true,bookmarked:row['bookmarked']===true||number(bookmark['id'],0)>0,
      bookmarkId:number(bookmark['id'],number(row['bookmark_id'],0)),hidden:row['hidden']===true,deleted:!!row['deleted_at']||row['user_deleted']===true,
      created:string(row['created_at']),replyTo:number(row['reply_to_post_number'],0),images:array(row['native_images']).filter((x:Object)=>typeof x==='string').map((x:Object)=>String(x))};
  }).filter((item:ForumPost)=>item.id>0);
}
export function mergeForumPosts(current:ForumPost[],incoming:ForumPost[]):ForumPost[]{
  const result=current.filter((post:ForumPost)=>!incoming.some((item:ForumPost)=>item.id===post.id)).concat(incoming);
  return result.sort((a:ForumPost,b:ForumPost)=>a.number-b.number);
}
export function missingForumPosts(stream:Object[],posts:ForumPost[],count:number=20):number[]{
  return stream.map((value:Object)=>number(value,0)).filter((id:number)=>id>0&&!posts.some((post:ForumPost)=>post.id===id)).slice(0,Math.min(100,Math.max(1,count)));
}
export function forumNotifications(value:Object):ForumNotification[]{return array(object(value)['notifications']).map((item:Object):ForumNotification=>{
 const row=object(item),data=object(row['data']);return {id:number(row['id'],0),type:number(row['notification_type'],0),read:row['read']===true,topicId:number(row['topic_id'],0),postNumber:number(row['post_number'],1),
 title:forumText(row['fancy_title']||data['topic_title']||data['badge_name']),actor:string(data['display_username']||data['original_username']||data['username'])};});}
export function notificationLabel(type:number):string {if(type===1)return'提及了你';if(type===2)return'回复了你';if(type===3)return'引用了你';if(type===5)return'赞了你的帖子';if(type===6)return'给你发来消息';if(type===12)return'获得徽章';return'社区通知';}
export function searchForumTopics(value:Object):ForumTopic[]{const empty: WireObject = {}; const data=object(value),topics=array(data['topics']).map(forumTopic);return array(data['posts']).map((item:Object):ForumTopic=>{
 const row=object(item),found=topics.find((topic:ForumTopic)=>topic.id===number(row['topic_id'],0));
 return found?{id:found.id,title:found.title,replies:found.replies,views:found.views,likes:found.likes,closed:found.closed,pinned:found.pinned,categoryId:found.categoryId,activity:found.activity,excerpt:forumText(row['blurb'])}:forumTopic(empty);
}).filter((topic:ForumTopic)=>topic.id>0).filter((topic:ForumTopic,index:number,all:ForumTopic[])=>all.findIndex((item:ForumTopic)=>item.id===topic.id)===index);}
export function forumUploadMarkdown(value:Object):string {const row=object(value),address=string(row['short_url']||row['url']);
 if(!/^(?:upload:\/\/|https:\/\/|\/)[^\s<>]+$/.test(address))throw new Error('上传结果未提供可用图片地址');
 return `![${string(row['original_filename']).replace(/[\[\]\\]/g,'')||'图片'}](${address.replace(/\)/g,'%29')})`;
}
export interface ForumDraft {title:string;raw:string;categoryId:number;}
const drafts:Map<string,ForumDraft>=new Map();
export function forumDraft(key:string):ForumDraft{return drafts.get(key)||{title:'',raw:'',categoryId:0};}
export function saveForumDraft(key:string,value:ForumDraft):void{if(value.title||value.raw||value.categoryId)drafts.set(key,value);else drafts.delete(key);}
