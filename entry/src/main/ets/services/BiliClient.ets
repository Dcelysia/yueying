// Adapted from Yueying/PiliPlus endpoint and WBI behavior; GPL-3.0.
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface VideoOwner { name: string; mid: number; face: string }
export interface VideoStats { view: number; danmaku?: number }
export interface VideoPart { cid: number; page: number; part: string; duration: number }
export interface Video {
  preview?: boolean;
  type?: number; attr?: number; mid?: number; aid: number; cover?: string; upper?: VideoOwner; id?: number; bvid: string; title: string; pic: string; duration: number | string;
  owner?: VideoOwner; author?: string; stat?: VideoStats; play?: number;
  epid?: number; seasonId?: number; historyCid?: number; historyPositionMs?: number;
  pages?: VideoPart[]; desc?: string; goto?: string; ad_info?: Object;
}
export interface Account { demo?: boolean; mid: number; uname: string; face: string; isLogin: boolean; money?: number }
export interface QrLogin { qrcode_key: string; url: string; code?: number; message?: string }
export interface FavoriteFolder { id: number; title: string; media_count: number }
export interface Creator { upic?: string; usign?: string; mid: number; name?: string; uname?: string; face: string; sign?: string; fans?: number }
export interface DynamicArchive { preview?: boolean; aid: string; bvid: string; title: string; cover: string; duration_text?: string }
interface DynamicPicture { url?: string; src?: string }
interface DynamicOpus { title?: string; summary?: DynamicDescription; pics?: DynamicPicture[] }
interface DynamicDraw { items?: DynamicPicture[] }
interface DynamicMajor { archive?: DynamicArchive; opus?: DynamicOpus; draw?: DynamicDraw }
interface DynamicBody { desc?: DynamicDescription; major?: DynamicMajor }
interface DynamicDescription { text: string }
interface DynamicAuthor { name: string; face: string; mid: number; pub_time: string }
interface DynamicModules { module_author: DynamicAuthor; module_dynamic: DynamicBody }
export interface DynamicItem { type?: string; orig?: DynamicItem; id_str: string; modules: DynamicModules }
export interface DynamicPage { v_voucher?: string; items: DynamicItem[]; offset: string; has_more: boolean }
interface DynamicResponse { code: number; message: string; data: DynamicPage }
interface HistoryIdentity { oid: number; cid: number; bvid: string; business: string }
interface HistoryEntry { title: string; cover: string; author_name: string; history: HistoryIdentity; progress: number; duration: number }
export interface HistoryCursor { max: number; view_at: number }
export interface HistoryResult { videos: Video[]; cursor: HistoryCursor }
export interface HistoryData { v_voucher?: string; list: HistoryEntry[]; cursor: HistoryCursor }
interface HistoryResponse { code: number; message: string; data: HistoryData }
interface FavoriteData { list: FavoriteFolder[] }
interface FavoriteResponse { code: number; message: string; data: FavoriteData }
interface QrResponse { code: number; message: string; data: QrLogin }
interface AccountResponse { code: number; message: string; data: Account }
interface CreatorResponse { code: number; message: string; data: Creator }
interface FollowData { v_voucher?: string; list: Creator[]; result?: Creator[] }
interface FollowResponse { code: number; message: string; data: FollowData }
interface SpaceList { vlist: Video[] }
interface SpaceData { v_voucher?: string; list: SpaceList }
interface SpaceResponse { code: number; message: string; data: SpaceData }
interface ProgressData { last_play_cid: number; last_play_time: number }
interface ProgressResponse { code: number; message: string; data: ProgressData }
interface WbiImages { img_url: string; sub_url: string }
export interface ApiData {
  v_voucher?: string;
  medias?: Video[]; item?: Video[]; list?: Video[]; result?: Video[]; wbi_img?: WbiImages;
  b_3?: string; isLogin?: boolean; uname?: string; face?: string; mid?: number;
}
interface ApiResponse { code: number; message: string; data: ApiData }
interface DetailResponse { code: number; message: string; data: Video }
export class BiliClient {
  private key: string = '';
  private anonymousCookie: string = '';
  private accountCookies: string = '';
  private store?: preferences.Preferences;
  private accountGeneration: number = 0;
  private demoData?: DemoAccountData;
  private accountBeforeDemo?: Account;
  demoAvailable: boolean = false;
  account?: Account;
  get hasLoginCredentials(): boolean { return /(?:^|;\s*)SESSDATA=/.test(this.accountCookies); }
  onLoginProgress: (message: string) => void = () => {};
  onAccountChanged: () => void = () => {};
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.demoAvailable = context.applicationInfo.name === 'com.dcelysia.yueying.nativepreview';
    this.store = await preferences.getPreferences(context, { name: 'bili_account' });
    this.accountCookies = await this.store.get('cookies', '') as string;
    if (this.accountCookies) this.refreshAccount().catch(() => {});
  }
  async refreshAccount(): Promise<void> {
    if (this.demoData) return;
    const generation = this.accountGeneration;
    const response = JSON.parse(await this.request('/x/web-interface/nav')) as AccountResponse;
    if (generation !== this.accountGeneration) return;
    this.account = response.data?.isLogin ? response.data : undefined;
    this.onAccountChanged();
  }
  enableDemo(): void {
    if (!this.demoAvailable || this.demoData) return;
    ++this.accountGeneration; this.accountBeforeDemo = this.account; this.demoData = new DemoAccountData();
    this.account = this.demoData.account; this.onAccountChanged();
  }
  exitDemo(): void {
    if (!this.demoData) return;
    ++this.accountGeneration; this.demoData = undefined; this.account = this.accountBeforeDemo; this.accountBeforeDemo = undefined; this.onAccountChanged();
  }
  async logout(): Promise<void> {
    this.demoData = undefined; this.accountBeforeDemo = undefined;
    ++this.accountGeneration; this.accountCookies = ''; this.anonymousCookie = ''; this.account = undefined; this.key = '';
    await this.store?.delete('cookies'); await this.store?.flush(); this.onAccountChanged();
  }
  async searchHistory(): Promise<string[]> {
    const raw = await this.store?.get('searchHistory', '[]') as string || '[]';
    try { return JSON.parse(raw) as string[]; } catch (error) { return []; }
  }
  async rememberSearch(keyword: string): Promise<void> {
    const history = await this.searchHistory();
    const next = [keyword, ...history.filter((item: string) => item !== keyword)].slice(0, 30);
    await this.store?.put('searchHistory', JSON.stringify(next)); await this.store?.flush();
  }
  async clearSearchHistory(): Promise<void> { await this.store?.delete('searchHistory'); await this.store?.flush(); }
  private requireAccount(): void { if (!this.account) throw new Error('请先登录 B站账号'); }

  private async requestResponse(path: string, params: Record<string, string> = {}, passport: boolean = false): Promise<http.HttpResponse> {
    const query = Object.keys(params).sort().map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
    const client = http.createHttp();
    try {
      const response = await client.request(`https://${passport ? 'passport.bilibili.com' : 'api.bilibili.com'}${path}?${query}`, {
        method: http.RequestMethod.GET, usingCache: false, maxRedirects: 0, connectTimeout: 10000, readTimeout: 15000,
        header: { 'User-Agent': path.startsWith('/x/space/') ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36' : 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
          'Cache-Control': 'no-cache', 'Referer': path.startsWith('/x/space/') ? `https://space.bilibili.com/${params['mid'] || ''}` : 'https://www.bilibili.com/', 'Cookie': this.accountCookies + (this.accountCookies && this.anonymousCookie ? '; ' : '') + this.anonymousCookie }
      });
      if (response.responseCode !== 200) throw new Error(`请求失败（HTTP ${response.responseCode}）`);
      return response;
    } finally { client.destroy(); }
  }
  private async request(path: string, params: Record<string, string> = {}): Promise<string> {
    return (await this.requestResponse(path, params)).result as string;
  }
  private async data(path: string, params: Record<string, string> = {}, allowAnonymous: boolean = false): Promise<ApiData> {
    const response = JSON.parse(await this.request(path, params)) as ApiResponse;
    if (response.code !== 0 && !allowAnonymous) throw new Error(response.message || `请求失败 ${response.code}`);
    if (response.data?.v_voucher) throw new Error('B站要求安全验证，请登录后重试，或在官方客户端完成验证');
    return response.data;
  }
  private async signed(params: Record<string, string>): Promise<Record<string, string>> {
    if (!this.key) {
      const nav = await this.data('/x/web-interface/nav', {}, true);
      const images = nav.wbi_img;
      if (!images) throw new Error('暂时无法获取请求签名');
      const source = images.img_url.split('/').pop()!.split('.')[0] + images.sub_url.split('/').pop()!.split('.')[0];
      const indices = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13];
      this.key = indices.map((index: number) => source[index]).join('');
    }
    params['wts'] = `${Math.floor(Date.now() / 1000)}`;
    const keys = Object.keys(params).sort();
    keys.forEach((key: string) => { params[key] = params[key].replace(/[!'()*]/g, ''); });
    const query = keys.map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
    const md = cryptoFramework.createMd('MD5');
    await md.update({ data: new util.TextEncoder().encodeInto(query + this.key) });
    const digest = await md.digest();
    params['w_rid'] = Array.from(digest.data).map((value: number) => value.toString(16).padStart(2, '0')).join('');
    return params;
  }
  async videos(mode: string, page: number, keyword: string = ''): Promise<Video[]> {
    if (this.demoData && mode.startsWith('favorite:')) return page === 1 ? this.demoData.favoriteVideos(Number(mode.split(':')[1])) : [];
    if (this.demoData && mode.startsWith('creator:')) return page === 1 ? this.demoData.creatorVideos(Number(mode.split(':')[1])) : [];
    let data: ApiData;
    if (mode === 'search') {
      if (!this.anonymousCookie) {
        const identity = await this.data('/x/frontend/finger/spi');
        this.anonymousCookie = `buvid3=${identity.b_3 || ''}`;
      }
      data = await this.data('/x/web-interface/wbi/search/type', await this.signed({ 'search_type': 'video', 'keyword': keyword, 'page': `${page}`, 'page_size': '20', 'platform': 'pc', 'web_location': '1430654' } as Record<string, string>));

    } else if (mode.startsWith('favorite:')) {
      this.requireAccount(); data = await this.data('/x/v3/fav/resource/list', { 'media_id': mode.split(':')[1], 'pn': `${page}`, 'ps': '20', 'order': 'mtime', 'type': '0', 'tid': '0', 'platform': 'web' } as Record<string, string>);
    } else if (mode.startsWith('creator:')) {
      const response = JSON.parse(await this.request('/x/space/wbi/arc/search', await this.signed({ 'mid': mode.split(':')[1], 'pn': `${page}`, 'ps': '20', 'order': 'pubdate', 'platform': 'web' } as Record<string, string>))) as SpaceResponse;
      if (response.code !== 0) throw new Error(response.message);
      if (response.data?.v_voucher) throw new Error('B站要求安全验证，请登录后重试');
      return this.normalize(response.data.list?.vlist || []);
    } else if (mode === 'popular') {
      data = await this.data('/x/web-interface/popular', { 'pn': `${page}`, 'ps': '20' } as Record<string, string>);
    } else {
      data = await this.data('/x/web-interface/wbi/index/top/feed/rcmd', await this.signed({ 'version': '1', 'feed_version': 'V8', 'homepage_ver': '1', 'ps': '20', 'fresh_idx': `${page}`, 'brush': `${page}`, 'fresh_type': '4' } as Record<string, string>));
    }
    const items = data.item || data.list || data.result || data.medias || [];
    return this.normalize(data.medias ? items.filter((video: Video) => video.type === 2 && ((video.attr || 0) & 1) === 0) : items);
  }
  private normalize(items: Video[]): Video[] {
    items.forEach((video: Video) => { if (!video.aid) video.aid = video.id || 0; });
    return items.filter((video: Video) => video.aid > 0 && !video.ad_info && (!video.goto || video.goto === 'av')).map((video: Video) => {
      video.title = video.title.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&');
      video.pic = video.pic || video.cover || ''; if (!video.owner && video.upper) video.owner = video.upper;
      video.pic = video.pic.startsWith('//') ? `https:${video.pic}` : video.pic.replace('http:', 'https:');
      return video;
    });
  }
  async detail(aid: number, bvid: string = ''): Promise<Video> {
    const demoVideo = this.demoData?.videos.find((video: Video) => video.aid === aid);
    if (demoVideo) return demoVideo;
    const response = JSON.parse(await this.request('/x/web-interface/view', aid > 0 ? { 'aid': `${aid}` } as Record<string, string> : { 'bvid': bvid } as Record<string, string>)) as DetailResponse;
    if (response.code !== 0) throw new Error(response.message);
    const video = response.data;
    if (!video?.aid) throw new Error('视频信息暂不可用，请登录或在官方客户端完成验证后重试');
    if (this.account && video.pages?.length) {
      try {
        const progress = JSON.parse(await this.request('/x/player/wbi/v2', await this.signed({ 'aid': `${video.aid}`, 'cid': `${video.pages[0].cid}` } as Record<string, string>))) as ProgressResponse;
        if (progress.code === 0) { video.historyCid = progress.data.last_play_cid; video.historyPositionMs = Math.max(0, progress.data.last_play_time); }
      } catch (error) { /* Optional history cannot block selecting a video. */ }
    }
    return video;
  }
  async createQr(): Promise<QrLogin> {
    const response = JSON.parse((await this.requestResponse('/x/passport-login/web/qrcode/generate', {}, true)).result as string) as QrResponse;
    if (response.code !== 0 || !response.data.url || !response.data.qrcode_key) throw new Error('暂时无法生成二维码');
    return response.data;
  }
  async pollQr(key: string, isActive: () => boolean): Promise<number> {
    const generation = this.accountGeneration;
    const response = await this.requestResponse('/x/passport-login/web/qrcode/poll', { 'qrcode_key': key } as Record<string, string>, true);
    const body = JSON.parse(response.result as string) as QrResponse;
    if (body.code !== 0) throw new Error(body.message);
    const code = body.data.code === undefined ? -1 : body.data.code;
    if (code === 0 && isActive() && generation === this.accountGeneration) {
      this.onLoginProgress('B站已确认，正在保存登录状态…');
      const cookies: Record<string, string> = {};
      const cookiePattern = /(?:^|[;,\r\n])\s*(SESSDATA|bili_jct|DedeUserID|DedeUserID__ckMd5)=([^;,\r\n]+)/g;
      const headers = response.header as Record<string, string | string[]>;
      const rawCookies: string[] = [response.cookies || ''];
      for (const name of Object.keys(headers)) {
        if (name.toLowerCase() !== 'set-cookie') continue;
        const value = headers[name];
        if (typeof value === 'string') rawCookies.push(value);
        else if (Array.isArray(value)) rawCookies.push(value.join('\n'));
      }
      for (const raw of rawCookies) {
        cookiePattern.lastIndex = 0; let match = cookiePattern.exec(raw);
        while (match) { cookies[match[1]] = match[2]; match = cookiePattern.exec(raw); }
      }
      const urlPattern = /[?&](SESSDATA|bili_jct|DedeUserID|DedeUserID__ckMd5)=([^&]*)/g;
      let urlMatch = urlPattern.exec(body.data.url || '');
      while (urlMatch) {
        if (!cookies[urlMatch[1]]) cookies[urlMatch[1]] = decodeURIComponent(urlMatch[2]);
        urlMatch = urlPattern.exec(body.data.url || '');
      }
      if (!cookies['SESSDATA']) throw new Error('登录凭据未返回，请重新扫码');
      this.accountCookies = Object.keys(cookies).map((name: string) => `${name}=${cookies[name]}`).join('; ');
      await this.store?.put('cookies', this.accountCookies); await this.store?.flush();
      if (isActive() && generation === this.accountGeneration) await this.verifyLogin();
    }
    return code;
  }
  async verifyLogin(): Promise<void> {
    if (!this.hasLoginCredentials) throw new Error('尚未收到登录凭据，请刷新二维码重试');
    this.onLoginProgress('正在验证 B站账号…');
    await this.refreshAccount();
    if (!this.account?.isLogin) throw new Error('B站已确认，但账号验证未完成，请点“重试登录验证”');
  }
  async history(cursor: HistoryCursor): Promise<HistoryResult> {
    if (this.demoData) return { videos: cursor.max === 0 ? this.demoData.videos : [], cursor: { max: 1, view_at: 0 } };
    this.requireAccount();
    const response = JSON.parse(await this.request('/x/web-interface/history/cursor', { 'type': 'archive', 'ps': '20', 'max': `${cursor.max}`, 'view_at': `${cursor.view_at}` } as Record<string, string>)) as HistoryResponse;
    if (response.code !== 0) throw new Error(response.message);
    if (response.data?.v_voucher) throw new Error('B站要求安全验证，请登录后重试');
    const videos: Video[] = [];
    for (const item of response.data.list || []) {
      if (item.history?.business !== 'archive') continue;
      videos.push({ aid: item.history.oid, bvid: item.history.bvid, title: item.title, pic: item.cover, duration: item.duration,
        author: item.author_name, historyCid: item.history.cid, historyPositionMs: Math.max(0, item.progress) * 1000 });
    }
    return { videos: this.normalize(videos), cursor: response.data.cursor };
  }
  async favoriteFolders(): Promise<FavoriteFolder[]> {
    if (this.demoData) return this.demoData.folders;
    this.requireAccount();
    const response = JSON.parse(await this.request('/x/v3/fav/folder/created/list-all', { 'up_mid': `${this.account!.mid}`, 'type': '2' } as Record<string, string>)) as FavoriteResponse;
    if (response.code !== 0) throw new Error(response.message);
    return response.data.list || [];
  }
  async followings(page: number): Promise<Creator[]> {
    if (this.demoData) return page === 1 ? this.demoData.creators : [];
    this.requireAccount();
    const response = JSON.parse(await this.request('/x/relation/followings', { 'vmid': `${this.account!.mid}`, 'pn': `${page}`, 'ps': '20', 'order': 'desc' } as Record<string, string>)) as FollowResponse;
    if (response.code !== 0) throw new Error(response.message);
    return response.data.list || [];
  }
  async searchCreators(keyword: string, page: number): Promise<Creator[]> {
    if (!this.anonymousCookie) { const identity = await this.data('/x/frontend/finger/spi'); this.anonymousCookie = `buvid3=${identity.b_3 || ''}`; }
    const response = JSON.parse(await this.request('/x/web-interface/wbi/search/type', await this.signed({ 'search_type': 'bili_user', 'keyword': keyword, 'page': `${page}`, 'page_size': '20', 'platform': 'pc', 'web_location': '1430654' } as Record<string, string>))) as FollowResponse;
    if (response.code !== 0) throw new Error(response.message);
    if (response.data?.v_voucher) throw new Error('B站要求安全验证，请登录后重试');
    return (response.data.result || []).map((creator: Creator) => {
      creator.face = (creator.face || creator.upic || '').replace(/^\/\//, 'https://').replace('http:', 'https:'); creator.sign = creator.sign || creator.usign;
      return creator;
    });
  }
  async creator(mid: number): Promise<Creator> {
    const demoCreator = this.demoData?.creators.find((creator: Creator) => creator.mid === mid);
    if (demoCreator) return demoCreator;
    const response = JSON.parse(await this.request('/x/space/wbi/acc/info', await this.signed({ 'mid': `${mid}`, 'token': '', 'platform': 'web' } as Record<string, string>))) as CreatorResponse;
    if (response.code !== 0) throw new Error(response.message);
    return response.data;
  }
  async dynamics(offset: string = ''): Promise<DynamicPage> {
    if (this.demoData) return { items: offset ? [] : this.demoData.dynamics(), offset: 'demo-end', has_more: false };
    this.requireAccount();
    const response = JSON.parse(await this.request('/x/polymer/web-dynamic/v1/feed/all', { 'type': 'all', 'offset': offset, 'features': 'itemOpusStyle' } as Record<string, string>)) as DynamicResponse;
    if (response.code !== 0) throw new Error(response.message);
    if (response.data?.v_voucher) throw new Error('B站要求安全验证，请登录后重试');
    return response.data;
  }
}

// Local preview fixtures. No cookies, API identity or playable media is fabricated.
class DemoAccountData {
  account: Account = { mid: 990000000, uname: '跃映体验官', face: 'resource://RAWFILE/demo_avatar.svg', isLogin: true, money: 128, demo: true };
  creators: Creator[] = [
    { mid: 990001001, uname: '山野来信（演示）', face: 'resource://RAWFILE/demo_avatar.svg', sign: '把山川湖海，装进平凡日常', fans: 286000 },
    { mid: 990001002, uname: '一间小厨房（演示）', face: 'resource://RAWFILE/demo_avatar.svg', sign: '认真做饭，也认真生活', fans: 157000 },
    { mid: 990001003, uname: '白日放映室（演示）', face: 'resource://RAWFILE/demo_avatar.svg', sign: '分享电影、音乐和生活里的灵感', fans: 42000 }
  ];
  folders: FavoriteFolder[] = [
    { id: 990010001, title: '演示 · 周末与远方', media_count: 3 },
    { id: 990010002, title: '演示 · 下次一定学会', media_count: 3 },
    { id: 990010003, title: '演示 · 留给安静的晚上', media_count: 2 }
  ];
  videos: Video[] = [];
  constructor() {
    const titles = ['去山里过一个没有闹钟的周末', '下班后，给自己做一顿好吃的', '书桌改造｜让生活多一点松弛感', '沿着海岸线，慢慢走到日落', '三个食材，做一份简单的早餐', '适合雨天循环播放的轻音乐', '在城市里寻找一片自己的绿地', '这部电影，值得留到周末慢慢看'];
    const covers = ['demo_landscape.svg', 'demo_kitchen.svg', 'demo_desk.svg'];
    for (let index = 0; index < titles.length; ++index) {
      const creator = this.creators[index % this.creators.length];
      this.videos.push({ aid: 990100001 + index, bvid: '', title: '演示 · ' + titles[index], pic: 'resource://RAWFILE/' + covers[index % covers.length],
        duration: 420 + index * 93, preview: true, owner: { mid: creator.mid, name: creator.uname!, face: creator.face }, stat: { view: 128000 + index * 17431 },
        historyCid: 990200001 + index, historyPositionMs: 45000 + index * 12000,
        pages: [{ cid: 990200001 + index, page: 1, part: '完整视频（演示）', duration: 420 + index * 93 }],
        desc: '这是本地演示数据，用于查看登录后的界面、收藏、历史和动态布局。人物、账号资料、视频标题及播放记录均为虚构，不关联真实 B站账号或视频。演示视频不会发送到电视。' });
    }
  }
  favoriteVideos(folder: number): Video[] { return this.videos.filter((_video: Video, index: number) => index % 3 === folder - 990010001); }
  creatorVideos(mid: number): Video[] { return mid === this.account.mid ? this.videos : this.videos.filter((video: Video) => video.owner?.mid === mid); }
  dynamics(): DynamicItem[] {
    const first = this.creators[0]; const second = this.creators[1]; const third = this.creators[2]; const video = this.videos[0];
    return [
      { id_str: 'demo-dynamic-1', type: 'DYNAMIC_TYPE_AV', modules: { module_author: { mid: first.mid, name: first.uname!, face: first.face, pub_time: '今天 10:20 · 演示数据' },
        module_dynamic: { desc: { text: '演示动态｜把周末交给山野，把风景留在客厅的大屏上。新的视频更新啦。' }, major: { archive: { aid: `${video.aid}`, bvid: '', title: video.title, cover: video.pic, duration_text: '07:00', preview: true } } } } },
      { id_str: 'demo-dynamic-2', type: 'DYNAMIC_TYPE_DRAW', modules: { module_author: { mid: second.mid, name: second.uname!, face: second.face, pub_time: '昨天 18:36 · 演示数据' },
        module_dynamic: { desc: { text: '演示动态｜今天也有好好吃饭。整理了几张日常，愿你的一天也有小小的惊喜。' }, major: { draw: { items: [{ src: 'resource://RAWFILE/demo_kitchen.svg' }, { src: 'resource://RAWFILE/demo_desk.svg' }, { src: 'resource://RAWFILE/demo_landscape.svg' }] } } } } },
      { id_str: 'demo-dynamic-3', type: 'DYNAMIC_TYPE_WORD', modules: { module_author: { mid: third.mid, name: third.uname!, face: third.face, pub_time: '2 天前 · 演示数据' },
        module_dynamic: { desc: { text: '演示动态｜下次想做一期周末片单：轻松、有趣，又能让人记住一点什么。你会把哪部电影放进收藏夹？\n\n这里是本地假数据，仅展示页面效果。' } } } }
    ];
  }
}
