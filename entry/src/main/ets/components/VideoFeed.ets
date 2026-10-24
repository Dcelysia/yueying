import { BiliClient, Video, HistoryCursor } from '../services/BiliClient';

class VideoRow {
  first: Video;
  second?: Video;
  constructor(first: Video, second?: Video) { this.first = first; this.second = second; }
}
class VideoRows implements IDataSource {
  private rows: VideoRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): VideoRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener);
  }
  replace(videos: Video[]): void {
    const next: VideoRow[] = [];
    for (let index = 0; index < videos.length; index += 2) next.push(new VideoRow(videos[index], videos[index + 1]));
    this.rows = next;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}
@Component
export struct VideoFeed {
  api: BiliClient = new BiliClient();
  mode: string = 'recommended';
  keyword: string = '';
  onOpen: (video: Video) => void = () => {};
  onDetails: (video: Video) => void = () => {};
  onLogin?: () => void = undefined;
  onCreator: (mid: number) => void = () => {};
  @State busy: boolean = false;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  @State count: number = 0;
  @State hasMore: boolean = true;
  private source: VideoRows = new VideoRows();
  private videos: Video[] = [];
  private ids: Set<number> = new Set();
  private page: number = 0;
  private historyCursor: HistoryCursor = { max: 0, view_at: 0 };
  private generation: number = 0;
  private mounted: boolean = false;
  aboutToAppear(): void { this.mounted = true; if (this.page === 0) this.load(true); }
  aboutToDisappear(): void { this.mounted = false; ++this.generation; }
  private async load(reset: boolean): Promise<void> {
    if (this.busy || (!reset && !this.hasMore)) return;
    const generation = ++this.generation;
    const nextPage = reset ? 1 : this.page + 1;
    this.busy = true; this.errorText = '';
    try {
      let items: Video[];
      let nextCursor: HistoryCursor = this.historyCursor;
      if (this.mode === 'history') {
        const result = await this.api.history(reset ? { max: 0, view_at: 0 } : this.historyCursor);
        items = result.videos; nextCursor = result.cursor;
      } else { items = await this.api.videos(this.mode, nextPage, this.keyword); }
      if (!this.mounted || generation !== this.generation) return;
      if (reset) { this.videos = []; this.ids.clear(); }
      let added = 0;
      for (const video of items) {
        if (!this.ids.has(video.aid)) { this.ids.add(video.aid); this.videos.push(video); ++added; }
      }
      this.historyCursor = nextCursor; this.page = nextPage; this.count = this.videos.length; this.hasMore = added > 0;
      this.source.replace(this.videos);
    } catch (error) {
      if (this.mounted && generation === this.generation) this.errorText = (error as Error).message;
    } finally {
      if (this.mounted && generation === this.generation) { this.busy = false; this.refreshing = false; }
    }
  }
  private thumbnail(url: string): string {
    return /^https:\/\/[^/]*hdslb\.com\//.test(url) && !url.includes('@') ? `${url}@480w_270h_1c.webp` : url;
  }
  private duration(value: number | string): string {
    if (typeof value === 'string') return value;
    const seconds = Math.max(0, Math.floor(value));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }
  private views(video: Video): string {
    const count = Number(video.stat?.view || video.play || 0);
    return count >= 10000 ? `${(count / 10000).toFixed(1)}万播放` : `${count}播放`;
  }
  @Builder
  card(video: Video) {
    Column({ space: 7 }) {
      Column({ space: 7 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(this.thumbnail(video.pic)).width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Cover)
        Text(this.duration(video.duration)).fontSize(10).fontColor('#FFFFFF').padding({ left: 5, right: 5, top: 2, bottom: 2 }).backgroundColor('#66000000').borderRadius(4).margin(6)
      }.borderRadius(10).clip(true)
      Text(video.title).fontSize(14).fontColor('#202020').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).height(40).width('100%')
      Text(this.views(video)).fontSize(11).fontColor('#888888').maxLines(1).width('100%')
      }.alignItems(HorizontalAlign.Start).onClick(() => { this.onOpen(video); }).gesture(LongPressGesture().onAction(() => { this.onDetails(video); }))
      Text(video.owner?.name || video.author || '').fontSize(12).fontColor('#888888').maxLines(1).width('100%').onClick(() => { this.onCreator(video.owner?.mid || video.mid || 0); })
    }.alignItems(HorizontalAlign.Start).padding({ bottom: 12 })
  }
  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 8 }) {
        if (this.errorText) { ListItem() { Text(this.errorText).fontSize(14).fontColor('#D8353F').padding(12) } }
        LazyForEach(this.source, (row: VideoRow) => {
          ListItem() {
            Row({ space: 10 }) {
              Column() { this.card(row.first) }.layoutWeight(1)
              Column() { if (row.second) { this.card(row.second) } }.layoutWeight(1)
            }.alignItems(VerticalAlign.Top)
          }
        }, (row: VideoRow) => `${row.first.aid}:${row.second?.aid || 0}`)
        ListItem() {
          Row() {
            if (this.busy) { LoadingProgress().width(26).height(26) }
            else if (this.errorText) { Button('重试').onClick(() => { this.load(this.count === 0); }); if (this.onLogin && this.errorText.includes('验证')) { Button('登录后重试').onClick(() => { this.onLogin?.(); }) } }
            else { Text(this.hasMore ? '上拉加载更多' : this.count === 0 ? '暂无视频' : '已经到底了').fontSize(13).fontColor('#888888') }
          }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 120 })
        }
      }.padding({ left: 12, right: 12 }).height('100%').scrollBar(BarState.Off).cachedCount(2)
        .onReachEnd(() => { if (!this.errorText && this.count > 0) this.load(false); })
    }.height('100%').onRefreshing(() => { this.load(true); })
  }
}
