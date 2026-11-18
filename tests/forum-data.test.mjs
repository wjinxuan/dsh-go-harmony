import test from 'node:test';import assert from 'node:assert/strict';
import {forumAuthCallback} from './ForumCallback.ts';
import {forumCategories,forumTopics,forumPosts,mergeForumPosts,missingForumPosts,searchForumTopics,forumNotifications,forumDraft,saveForumDraft,forumUploadMarkdown}from'./ForumData.ts';
test('Discourse category/topic contracts preserve order, counts and permission flags',()=>{
 assert.deepEqual(forumCategories({categories:[{id:2,name:'Second',position:2,permission:2},{id:1,name:'A &amp; B',position:1}]}).map(x=>[x.id,x.name,x.permission]),[[1,'A & B',0],[2,'Second',2]]);
 const [topic]=forumTopics({topic_list:{topics:[{id:1,title:'Topic',posts_count:4,pinned:true,closed:true}]}});assert.equal(topic.replies,3);assert.equal(topic.closed,true);
});
test('post stream supports sparse paging, bookmark id mapping, deleted and reactions',()=>{
 const first=forumPosts({bookmarks:[{id:9,bookmarkable_type:'Post',bookmarkable_id:2}],post_stream:{posts:[{id:2,post_number:2,cooked:'unused',native_markdown:'Actual content',actions_summary:[{id:2,count:3,acted:true,can_undo:true}]}]}});
 assert.equal(first[0].bookmarkId,9);assert.equal(first[0].liked,true);assert.equal(first[0].canUnlike,true);assert.equal(first[0].markdown,'Actual content');
 const second=forumPosts({posts:[{id:1,post_number:1,user_deleted:true},{id:2,post_number:2,native_markdown:'Updated'}]});const merged=mergeForumPosts(first,second);assert.deepEqual(merged.map(x=>x.id),[1,2]);assert.equal(merged[1].markdown,'Updated');assert.equal(merged[0].deleted,true);assert.deepEqual(missingForumPosts([1,2,3,4],merged,1),[3]);
});
test('search joins posts to topics and deduplicates while notifications retain target numbers',()=>{
 assert.equal(searchForumTopics({topics:[{id:3,title:'Matched'}],posts:[{topic_id:3,blurb:'<b>Hit</b>'},{topic_id:3},{topic_id:99}]}).length,1);
 const [notice]=forumNotifications({notifications:[{id:2,topic_id:3,post_number:7,notification_type:2,data:{topic_title:'Title',display_username:'actor'}}]});assert.equal(notice.actor,'actor');assert.equal(notice.postNumber,7);
});
test('drafts are isolated by forum and topic, upload links reject executable schemes',()=>{
 saveForumDraft('a:1',{title:'t',raw:'body',categoryId:2});assert.equal(forumDraft('a:1').raw,'body');assert.equal(forumDraft('b:1').raw,'');saveForumDraft('a:1',{title:'',raw:'',categoryId:0});assert.equal(forumDraft('a:1').raw,'');
 assert.equal(forumUploadMarkdown({short_url:'upload://hash.png',original_filename:'name.png'}),'![name.png](upload://hash.png)');assert.throws(()=>forumUploadMarkdown({url:'javascript:alert(1)'}));
});
test('callback accepts only one canonical RSA payload and rejects other actions, origins and ambiguous query strings',()=>{
 const payload=Buffer.alloc(256,255).toString('base64'),canonical='dshgo://forum/auth?payload='+encodeURIComponent(payload);
 assert.equal(forumAuthCallback(canonical),canonical);assert.equal(forumAuthCallback(canonical.replace('dshgo://forum','DSHGO://FORUM')),canonical);
 for(const value of ['https://forum/auth?payload='+payload,canonical+'&next=evil',canonical+'#fragment',canonical.replace('/auth?','/auth/../auth?'),canonical.replace('forum','forum.evil'),canonical.replace('payload=','payload=%'),canonical+'\n','dshgo://forum/auth?payload=a'.repeat(9000)])assert.equal(forumAuthCallback(value),undefined);
});
