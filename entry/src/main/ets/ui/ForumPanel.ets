import { localizedSettingsText, localizedSettingsFormat } from './SettingsLocale';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { array, object, string, number, WireObject } from '../dsh/DshWire';
import { ForumAuthState, ForumClient } from '../forum/ForumClient';
import { ForumCategory, ForumTopic, ForumPost, ForumNotification, forumCategories, forumTopics, forumPosts,
  mergeForumPosts, missingForumPosts, forumNotifications, notificationLabel, searchForumTopics, forumDraft, saveForumDraft, forumUploadMarkdown } from '../forum/ForumData';
import { TransportControl } from '../remote/TransportEndpoint';
import { pickAttachments, deleteAttachments, DraftAttachment } from './AttachmentPicker';
import { MessageBody } from './MessageBody';
import { ThemeColors, themeColors } from './DshTheme';
@Component
export struct ForumPanel {
  @StorageProp('dshLanguage') private localeLanguage: string = 'system';
  private t(value: string): string { return localizedSettingsText(value, this.localeLanguage); }
  private f(value: string, args: (string | number | boolean | null | undefined)[]): string { return localizedSettingsFormat(value, args, this.localeLanguage); }
  @Prop colors: ThemeColors = themeColors();
  @Prop @Watch('redirectChanged') authRedirect: string = '';
  getControl: () => Promise<TransportControl> = async () => { throw new Error('本机连接服务不可用'); };
  onClose: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  onOpenLink: (link: string) => void = () => {};
  onAuthRedirectConsumed: () => void = () => {};
  @State private auth: ForumAuthState = { 'baseUrl': '', signedIn: false, waiting: false, user: {} };
  @State private page: string = 'home';
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private notice: string = '';
  @State private categories: ForumCategory[] = [];
  @State private topics: ForumTopic[] = [];
  @State private posts: ForumPost[] = [];
  @State private notifications: ForumNotification[] = [];
  @State private feed: string = 'latest';
  @State private categoryId: number = 0;
  @State private topicId: number = 0;
  @State private topicTitle: string = '';
  @State private canCreate: boolean = false;
  @State private canReply: boolean = false;
  @State private more: boolean = false;
  @State private query: string = '';
  @State private baseDraft: string = '';
  @State private redirectDraft: string = '';
  @State private title: string = '';
  @State private raw: string = '';
  @State private composeCategory: number = 0;
  @State private replyTo: number = 0;
  @State private summary: string = '';
  @State private summaryUser: string = '';
  private client?: ForumClient;
  private active: boolean = false;
  private generation: number = 0;
  private pageNumber: number = 0;
  private stream: Object[] = [];
  private chunkSize: number = 20;
  private draftKey: string = '';
  private composeTopic: number = 0;
  private handledRedirect: string = '';
  private scroller: Scroller = new Scroller();
  aboutToAppear(): void { this.active = true;
    this.onBackHandler?.(() => { if (this.busy) return true; if (this.page === 'home') return false; this.back(); return true; });
    void this.initialize(); }
  aboutToDisappear(): void { this.onBackHandler?.(undefined); this.keepDraft(); this.active = false; this.generation++; this.client?.close(); this.client = undefined; }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private current(version: number): boolean { return this.active && version === this.generation; }
  private async task(work: (version: number) => Promise<void>): Promise<void> {
    if (this.busy || !this.active) return;
    const version = this.generation; this.busy = true; this.error = ''; this.notice = '';
    try { await work(version); }
    catch (error) { if (this.current(version)) { this.error = (error as Error).message || '社区请求未能完成';
      try { const state = await this.call('state'); if (this.current(version)) this.auth = this.client!.auth(state); } catch {}
    } }
    finally { if (this.current(version)) { this.busy = false;
      if (this.authRedirect && this.handledRedirect !== this.authRedirect && this.client) setTimeout(() => { this.redirectChanged(); }, 0);
    } }
  }
  private async initialize(): Promise<void> {
    await this.task(async (version: number) => {
      const client = new ForumClient(await this.getControl());
      if (!this.current(version)) { client.close(); return; }
      this.client = client; const auth = await client.unlock(); if (!this.current(version)) return; this.auth = auth; this.baseDraft = this.auth.baseUrl;
      if (this.authRedirect) await this.complete(this.authRedirect, version);
      await this.loadHome(version);
    });
  }
  private async call(action: string, args: WireObject = {}): Promise<Object> {
    if (!this.client) throw new Error('社区尚未连接，请重试');
    return this.client.call(action, args);
  }
  private redirectChanged(): void {
    if (this.authRedirect && this.handledRedirect !== this.authRedirect && this.client && !this.busy) void this.task(async (version: number) => {
      await this.complete(this.authRedirect, version); await this.loadHome(version);
    });
  }
  private async complete(link: string, version: number): Promise<void> {
    this.handledRedirect = link;
    try { const result = await this.call('complete', { 'redirect': link }); if (this.current(version)) this.auth = this.client!.auth(result); }
    finally { this.onAuthRedirectConsumed(); }
  }
  private async loadHome(version: number): Promise<void> {
    const site = await this.call('site');
    if (!this.current(version)) return;
    this.categories = forumCategories(site).filter((item: ForumCategory) => item.id !== number(object(site)['uncategorized_category_id'], 0)); await this.loadTopics(version, false);
  }
  private async loadTopics(version: number, next: boolean): Promise<void> {
    const category = this.categories.find((item: ForumCategory) => item.id === this.categoryId);
    const index = next ? this.pageNumber + 1 : 0;
    const value = await this.call('topics', { 'kind': this.feed, 'page': index, 'categoryId': this.categoryId, 'slug': category?.slug || '-' });
    if (!this.current(version)) return;
    const incoming = forumTopics(value);
    this.topics = next ? this.topics.concat(incoming.filter((item: ForumTopic) => !this.topics.some((known: ForumTopic) => known.id === item.id))) : incoming;
    this.more = !!string(object(object(value)['topic_list'])['more_topics_url']) && incoming.length > 0;
    this.canCreate = object(object(value)['topic_list'])['can_create_topic'] === true;
    this.pageNumber = index; this.page = 'home';
  }
  private chooseFeed(kind: string, category: number = 0): void {
    if (this.busy) return;
    this.feed = kind; this.categoryId = category;
    void this.task(async (version: number) => { await this.loadTopics(version, false); });
  }
  private async loadTopic(id: number, version: number, postNumber: number = 1): Promise<void> {
    const value = object(await this.call('topic', { 'id': id }));
    if (!this.current(version)) return;
    this.topicId = id; this.topicTitle = string(value['title']); this.posts = forumPosts(value);
    this.stream = array(object(value['post_stream'])['stream']); this.chunkSize = number(value['chunk_size'], 20);
    this.canReply = object(value['details'])['can_create_post'] === true && value['closed'] !== true && value['archived'] !== true;
    this.more = missingForumPosts(this.stream, this.posts, this.chunkSize).length > 0; this.page = 'topic';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    if (postNumber > 1) {
      for (let attempt = 0; attempt < 8 && this.more && !this.posts.some((post: ForumPost) => post.number >= postNumber); attempt++) {
        await this.morePosts(version); if (!this.current(version)) return;
      }
      const target = this.posts.find((post: ForumPost) => post.number >= postNumber);
      if (target) setTimeout(() => { if (!this.current(version) || this.page !== 'topic' || this.topicId !== id) return;
        try { const utils = this.getUIContext().getComponentUtils();
          const item = utils.getRectangleById('forum-post-' + target.id), container = utils.getRectangleById('forum-scroll');
          this.scroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, this.scroller.currentOffset().yOffset + this.getUIContext().px2vp(item.windowOffset.y - container.windowOffset.y)), animation: true });
        } catch {}
      }, 200);
    }
  }
  private async morePosts(version: number): Promise<void> {
    const ids = missingForumPosts(this.stream, this.posts, this.chunkSize); if (!ids.length) return;
    const value = await this.call('posts', { 'topicId': this.topicId, 'ids': ids });
    if (!this.current(version)) return;
    const incoming = forumPosts(value);
    this.posts = mergeForumPosts(this.posts, incoming);
    this.stream = this.stream.filter((value: Object) => !ids.includes(number(value, 0)) || incoming.some((post: ForumPost) => post.id === number(value, 0)));
    this.more = missingForumPosts(this.stream, this.posts, this.chunkSize).length > 0;
  }
  private async search(version: number, next: boolean): Promise<void> {
    const index = next ? this.pageNumber + 1 : 1;
    const value = await this.call('search', { 'query': this.query.trim(), 'page': index });
    if (!this.current(version)) return;
    const incoming = searchForumTopics(value);
    this.topics = next ? this.topics.concat(incoming.filter((item: ForumTopic) => !this.topics.some((known: ForumTopic) => known.id === item.id))) : incoming;
    const group = object(object(value)['grouped_search_result']);
    this.more = incoming.length > 0 && (group['more_posts'] === true || group['more_full_page_results'] === true);
    this.pageNumber = index; this.page = 'search';
  }
  private async loadNotifications(version: number, next: boolean): Promise<void> {
    const value = await this.call('notifications', { 'offset': next ? this.notifications.length : 0 });
    if (!this.current(version)) return;
    const incoming = forumNotifications(value); this.notifications = next ? this.notifications.concat(incoming) : incoming;
    this.more = incoming.length > 0 && !!string(object(value)['load_more_notifications']); this.page = 'notifications';
  }
  private async login(version: number): Promise<void> {
    const value = object(await this.call('begin'));
    if (!this.current(version)) return;
    await this.context().openLink(string(value['url']));
    if (this.current(version)) this.auth = this.client!.auth(await this.call('state'));
  }
  private keepDraft(): void { if (this.page === 'compose' && this.draftKey) saveForumDraft(this.draftKey, { 'title': this.title, 'raw': this.raw, 'categoryId': this.composeCategory }); }
  private compose(post?: ForumPost): void {
    if (!this.auth.signedIn || this.busy) return;
    this.composeTopic = this.page === 'topic' ? this.topicId : 0; this.replyTo = post?.number || 0;
    this.draftKey = this.auth.baseUrl + ':' + (this.composeTopic ? 'reply:' + this.composeTopic : 'topic');
    const draft = forumDraft(this.draftKey); this.title = draft.title; this.raw = draft.raw; this.composeCategory = draft.categoryId || this.categoryId;
    this.page = 'compose';
  }
  private async publish(version: number): Promise<void> {
    const value = object(await this.call(this.composeTopic ? 'reply' : 'createTopic', this.composeTopic ?
      { 'topicId': this.composeTopic, 'raw': this.raw, 'replyTo': this.replyTo } : { 'title': this.title, 'raw': this.raw, 'categoryId': this.composeCategory }));
    if (!this.current(version)) return;
    saveForumDraft(this.draftKey, { 'title': '', 'raw': '', 'categoryId': 0 }); this.draftKey = ''; this.raw = ''; this.title = '';
    if (value['action'] === 'enqueued') { await this.loadHome(version); this.notice = '帖子已提交，正在等待社区审核。'; return; }
    const post = object(value['post'] || value); const target = number(post['topic_id'], this.composeTopic);
    if (target) await this.loadTopic(target, version); else await this.loadHome(version);
    this.notice = '发布成功。';
  }
  private async upload(version: number): Promise<void> {
    let selected: DraftAttachment[] = [];
    try {
      selected = await pickAttachments(this.context(), 'photos', 1, 10 * 1024 * 1024, () => this.current(version));
      const item = selected[0]; if (!item || !this.current(version)) return;
      const file = await fileIo.open(item.path, fileIo.OpenMode.READ_ONLY);
      const bytes = new ArrayBuffer(item.size);
      try { if (await fileIo.read(file.fd, bytes) !== item.size) throw new Error('图片未能完整读取'); }
      finally { await fileIo.close(file); }
      const data = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
      const value = await this.call('upload', { 'filename': item.name.slice(0, 128), 'data': data });
      if (this.current(version)) { this.raw += '\n' + forumUploadMarkdown(value) + '\n'; this.keepDraft(); }
    } finally { await deleteAttachments(selected); }
  }
  private async attachShare(version: number): Promise<void> {
    const data = await pasteboard.getSystemPasteboard().getData(); const value = data.getPrimaryText();
    const link = /(?:https:\/\/[^\s<>]+#p=[^\s<>]+|dshgo:\/\/share\/[^\s<>]+)/.exec(value)?.[0];
    if (!link) throw new Error('请先复制分享面板生成的配置或插件链接。');
    if (this.current(version)) { this.raw += `\n[分享码](${link.replace(/\)/g, '%29')})\n`; this.keepDraft(); }
  }
  private async postAction(post: ForumPost, action: string, version: number): Promise<void> {
    const result = object(await this.call(action, { 'id': action === 'unbookmark' ? post.bookmarkId : post.id }));
    if (!this.current(version)) return;
    this.posts = this.posts.map((item: ForumPost): ForumPost => {
      if (item.id !== post.id) return item;
      return { 'id': item.id, 'topicId': item.topicId, number: item.number, 'username': item.username, name: item.name, markdown: item.markdown,
        likes: Math.max(0, item.likes + (action === 'like' ? 1 : action === 'unlike' ? -1 : 0)), liked: action === 'like' ? true : action === 'unlike' ? false : item.liked,
        canLike: action === 'unlike' ? true : item.canLike, canUnlike: action === 'like' ? true : item.canUnlike,
        bookmarked: action === 'bookmark' ? true : action === 'unbookmark' ? false : item.bookmarked,
        bookmarkId: action === 'bookmark' ? number(result['id'], 0) : action === 'unbookmark' ? 0 : item.bookmarkId,
        hidden: item.hidden, deleted: item.deleted, created: item.created, 'replyTo': item.replyTo, images: item.images };
    });
  }
  private openLink(link: string): void {
    if (link.startsWith(this.auth.baseUrl + '/t/')) {
      const match = /^\/t\/(?:[^/]+\/)?([0-9]+)(?:\/([0-9]+))?(?:[?#].*)?$/.exec(link.slice(this.auth.baseUrl.length));
      if (match) { void this.task(async (version: number) => { await this.loadTopic(Number(match[1]), version, Number(match[2] || 1)); }); return; }
    }
    this.onOpenLink(link);
  }
  private back(): void {
    if (this.busy) return;
    this.keepDraft();
    if (this.page === 'home') this.onClose();
    else if (this.page === 'compose' && this.composeTopic) this.page = 'topic';
    else { this.page = 'home'; void this.task(async (version: number) => { await this.loadTopics(version, false); }); }
  }
  @Builder private topicCard(topic: ForumTopic) {
    Column({ space: 7 }) {
      Text(`${topic.pinned ? this.t('置顶 · ') : ''}${topic.closed ? this.t('已关闭 · ') : ''}${topic.title}`).fontSize(16).fontColor(this.colors.text).fontWeight(FontWeight.Medium).width('100%');
      if (topic.excerpt) Text(topic.excerpt).fontSize(13).fontColor(this.colors.muted).maxLines(3).width('100%');
      Text(this.f('{0} 回复 · {1} 浏览 · {2} 赞', [topic.replies, topic.views, topic.likes])).fontSize(12).fontColor(this.colors.muted).width('100%');
    }.width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(12).onClick(() => { void this.task(async (version: number) => { await this.loadTopic(topic.id, version); }); });
  }
  @Builder private postCard(post: ForumPost) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(post.username).fontSize(14).fontColor(this.colors.primary).layoutWeight(1).onClick(() => { void this.task(async (version: number) => {
          const value = object(object(await this.call('user', { 'username': post.username }))['user_summary']);
          if (this.current(version)) { this.summaryUser = post.username; this.summary = this.f('{0} 个主题 · {1} 条回复\n收到 {2} 个赞 · 送出 {3} 个赞\n访问 {4} 天 · {5} 个解决方案', [number(value['topic_count'], 0), number(value['post_count'], 0), number(value['likes_received'], 0), number(value['likes_given'], 0), number(value['days_visited'], 0), number(value['solved_count'], 0)]); this.page = 'user'; }
        }); });
        Text('#' + post.number).fontSize(12).fontColor(this.colors.muted);
      }.width('100%');
      if (post.replyTo) Text('回复 #' + post.replyTo).fontSize(12).fontColor(this.colors.muted);
      if (post.hidden || post.deleted) Text(this.t(post.deleted ? '此帖子已删除。' : '此帖子已被隐藏。')).fontSize(13).fontColor(this.colors.muted);
      else {
        MessageBody({ text: post.markdown, colors: this.colors, onOpenLink: (link: string) => { this.openLink(link); } });
        ForEach(post.images, (source: string) => { Image(source).width('100%').height(180).objectFit(ImageFit.Contain).onClick(() => { this.onOpenLink(source); }); }, (source: string) => source);
      }
      Row({ space: 8 }) {
        Button(`${this.t(post.liked ? '已赞' : '赞')} ${post.likes}`).height(32).fontSize(12).enabled(this.auth.signedIn && !this.busy && (post.liked ? post.canUnlike : post.canLike))
          .onClick(() => { void this.task(async (version: number) => { await this.postAction(post, post.liked ? 'unlike' : 'like', version); }); });
        Button(this.t(post.bookmarked ? '取消收藏' : '收藏')).height(32).fontSize(12).enabled(this.auth.signedIn && !this.busy && (!post.bookmarked || post.bookmarkId > 0))
          .onClick(() => { void this.task(async (version: number) => { await this.postAction(post, post.bookmarked ? 'unbookmark' : 'bookmark', version); }); });
        Button(this.t('回复')).height(32).fontSize(12).enabled(this.auth.signedIn && this.canReply && !this.busy).onClick(() => { this.compose(post); });
      }
      Row({ space: 8 }) {
        Button(this.t('复制链接')).height(28).fontSize(12).onClick(() => { void pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.auth.baseUrl + '/t/topic/' + this.topicId + '/' + post.number)).catch(() => {}); });
        Button(this.t('在浏览器打开')).height(28).fontSize(12).onClick(() => { this.onOpenLink(this.auth.baseUrl + '/t/topic/' + this.topicId + '/' + post.number); });
      }
    }.id('forum-post-' + post.id).alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor(this.colors.surface).borderRadius(12);
  }
  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button(this.t('返回')).height(38).fontSize(13).enabled(!this.busy).onClick(() => { this.back(); });
        Text(this.page === 'topic' ? this.topicTitle : this.t('社区')).fontSize(18).fontColor(this.colors.text).layoutWeight(1).maxLines(1);
        Button(this.auth.signedIn ? string(this.auth.user['username']) || '账号' : '登录').height(38).fontSize(13).enabled(!this.busy)
          .onClick(() => { this.page = 'account'; });
      }.width('100%').padding({ left: 12, right: 12 });
      if (this.busy) Progress({ value: 35, total: 100, type: ProgressType.Linear }).width('100%');
      if (this.error) Text(this.t(this.error)).fontSize(13).fontColor(this.colors.danger).padding(10);
      if (this.notice) Text(this.t(this.notice)).fontSize(13).fontColor(this.colors.success).padding(10);
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          if (this.page === 'home' || this.page === 'search') {
            Row({ space: 6 }) {
              TextInput({ placeholder: this.t('搜索社区'), text: this.query }).layoutWeight(1).onChange((value: string) => { this.query = value; });
              Button(this.t('搜索')).height(36).enabled(!this.busy && !!this.query.trim()).onClick(() => { void this.task(async (version: number) => { await this.search(version, false); }); });
            }.width('100%');
            Scroll() { Row({ space: 6 }) {
              Button(this.t('最新')).height(32).onClick(() => { this.chooseFeed('latest'); });
              Button(this.t('热门')).height(32).onClick(() => { this.chooseFeed('top'); });
              ForEach(this.categories.filter((category: ForumCategory) => category.parent === 0), (category: ForumCategory) => {
                Button(category.name).height(32).fontSize(12).onClick(() => { this.chooseFeed('category', category.id); });
              }, (category: ForumCategory) => String(category.id));
            } }.scrollable(ScrollDirection.Horizontal).width('100%');
            Row({ space: 8 }) {
              Button(this.t('发布主题')).height(34).fontSize(13).enabled(this.auth.signedIn && this.canCreate && !this.busy).onClick(() => { this.compose(); });
              Button(this.t('通知')).height(34).fontSize(13).enabled(this.auth.signedIn && !this.busy).onClick(() => { void this.task(async (version: number) => { await this.loadNotifications(version, false); }); });
              Button(this.t('刷新')).height(34).fontSize(13).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.loadHome(version); }); });
            }
            ForEach(this.topics, (topic: ForumTopic) => { this.topicCard(topic); }, (topic: ForumTopic) => String(topic.id));
            if (!this.topics.length && !this.busy) Text(this.t('暂无主题')).fontColor(this.colors.muted);
            if (this.more) Button(this.t('加载更多')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { if (this.page === 'search') await this.search(version, true); else await this.loadTopics(version, true); }); });
          } else if (this.page === 'topic') {
            Text(this.topicTitle).fontSize(20).fontColor(this.colors.text).width('100%');
            ForEach(this.posts, (post: ForumPost) => { this.postCard(post); }, (post: ForumPost) => String(post.id));
            if (this.more) Button(this.t('加载更多回复')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.morePosts(version); }); });
            Button(this.t('回复主题')).enabled(this.auth.signedIn && this.canReply && !this.busy).onClick(() => { this.compose(); });
          } else if (this.page === 'notifications') {
            Button(this.t('全部标为已读')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.call('markRead'); await this.loadNotifications(version, false); }); });
            ForEach(this.notifications, (item: ForumNotification) => {
              Column({ space: 6 }) {
                Text(`${item.read ? '' : '● '}${item.actor} ${this.t(notificationLabel(item.type))}`).fontSize(14).fontColor(this.colors.text).width('100%');
                Text(item.title).fontSize(13).fontColor(this.colors.muted).width('100%');
              }.width('100%').padding(12).backgroundColor(this.colors.surface).borderRadius(12).onClick(() => { void this.task(async (version: number) => {
                await this.call('markRead', { 'id': item.id }); if (item.topicId) await this.loadTopic(item.topicId, version, item.postNumber); else await this.loadNotifications(version, false);
              }); });
            }, (item: ForumNotification) => String(item.id));
            if (this.more) Button(this.t('更多通知')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.loadNotifications(version, true); }); });
          } else if (this.page === 'compose') {
            Text(this.composeTopic ? this.f('回复：{0}{1}', [this.topicTitle, this.replyTo ? ' #' + this.replyTo : '']) : this.t('发布主题')).fontSize(17).fontColor(this.colors.text).width('100%');
            if (!this.composeTopic) {
              TextInput({ placeholder: this.t('主题标题'), text: this.title }).enabled(!this.busy).onChange((value: string) => { this.title = value; this.keepDraft(); });
              Select(this.categories.filter((item: ForumCategory) => item.permission === 1 || item.permission === 0).map((item: ForumCategory): SelectOption => { return { value: item.name }; }))
                .value(this.categories.find((item: ForumCategory) => item.id === this.composeCategory)?.name || this.t('选择分类'))
                .onSelect((index: number) => { this.composeCategory = this.categories.filter((item: ForumCategory) => item.permission === 1 || item.permission === 0)[index]?.id || 0; this.keepDraft(); });
            }
            TextArea({ placeholder: this.t('使用 Markdown 编写帖子'), text: this.raw }).height(260).enabled(!this.busy).onChange((value: string) => { this.raw = value; this.keepDraft(); });
            Row({ space: 8 }) {
              Button(this.t('上传图片')).fontSize(13).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.upload(version); }); });
              Column({ space: 2 }) {
                Text(this.t('附上分享码')).fontSize(12).fontColor(this.colors.muted);
                PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
                  .enabled(!this.busy).onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                    if (result === PasteButtonOnClickResult.SUCCESS) void this.task(async (version: number) => { await this.attachShare(version); });
                    else this.error = this.t('未能获得本次剪贴板访问授权。');
                  });
              }
              Button(this.t('发布')).fontSize(13).enabled(!this.busy && !!this.raw.trim() && (!!this.composeTopic || !!this.title.trim()))
                .onClick(() => { void this.task(async (version: number) => { await this.publish(version); }); });
            }
            if (this.raw) MessageBody({ text: this.raw, colors: this.colors, onOpenLink: (link: string) => { this.openLink(link); } });
          } else if (this.page === 'account') {
            Text(this.auth.signedIn ? '已登录：' + string(this.auth.user['username']) : '登录社区后可发帖、回复、点赞、收藏与接收通知。').fontSize(14).fontColor(this.colors.text);
            if (!this.auth.signedIn) {
              Button(this.t(this.auth.waiting ? '重新打开登录' : '在浏览器登录社区')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { await this.login(version); }); });
              if (this.auth.waiting) Button(this.t('取消登录')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { const value = await this.call('cancel'); if (this.current(version)) this.auth = this.client!.auth(value); }); });
              TextInput({ placeholder: this.t('如未自动返回，可粘贴 dshgo://forum/auth 回调'), text: this.redirectDraft }).onChange((value: string) => { this.redirectDraft = value; });
              Button(this.t('完成登录')).enabled(!this.busy && !!this.redirectDraft).onClick(() => { void this.task(async (version: number) => { await this.complete(this.redirectDraft, version); this.redirectDraft = ''; }); });
            } else Button(this.t('退出社区账号')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { const value = await this.call('signOut'); if (this.current(version)) this.auth = this.client!.auth(value); }); });
            TextInput({ placeholder: this.t('社区地址'), text: this.baseDraft }).enabled(!this.busy).onChange((value: string) => { this.baseDraft = value; });
            Button(this.t('保存社区地址')).enabled(!this.busy).onClick(() => { void this.task(async (version: number) => { const value = await this.call('setBase', { 'baseUrl': this.baseDraft }); if (this.current(version)) { this.auth = this.client!.auth(value); this.baseDraft = this.auth.baseUrl; this.feed = 'latest'; this.categoryId = 0; await this.loadHome(version); } }); });
          } else if (this.page === 'user') {
            Text(this.summaryUser).fontSize(20).fontColor(this.colors.text); Text(this.summary).fontSize(15).fontColor(this.colors.muted);
          }
        }.width('100%').padding(12).alignItems(HorizontalAlign.Start);
      }.id('forum-scroll').width('100%').layoutWeight(1);
    }.width('100%').height('100%').backgroundColor(this.colors.background);
  }
}
