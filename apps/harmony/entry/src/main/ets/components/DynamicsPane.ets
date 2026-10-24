import { BiliClient, Account, DynamicItem, Video } from '../services/BiliClient';
import { PagedItems } from './PagedItems';

@Component
export struct DynamicsPane {
  api: BiliClient = new BiliClient();
  @Prop @Watch('accountChanged') account: Account | undefined = undefined;
  onLogin: () => void = () => {};
  onVideo: (video: Video) => void = () => {};
  onCreator: (mid: number) => void = () => {};
  onImages: (images: string[]) => void = () => {};
  @State busy: boolean = false;
  @State errorText: string = '';
  @State count: number = 0;
  @State hasMore: boolean = true;
  @State collapsedDynamicIds: string[] = [];
  private source: PagedItems<DynamicItem> = new PagedItems();
  private feedOffset: string = '';
  private generation: number = 0;
  private mounted: boolean = false;
  private ids: Set<string> = new Set();
  aboutToAppear(): void { this.mounted = true; if (this.account && !this.count) this.load(); }
  aboutToDisappear(): void { this.mounted = false; ++this.generation; }
  private accountChanged(): void {
    ++this.generation; this.source.clear(); this.ids.clear(); this.count = 0; this.collapsedDynamicIds = []; this.feedOffset = ''; this.busy = false; this.hasMore = true;
    if (this.mounted && this.account) this.load();
  }
  private async load(): Promise<void> {
    if (this.busy || !this.hasMore || !this.account) return;
    const generation = this.generation; this.busy = true; this.errorText = '';
    try {
      const page = await this.api.dynamics(this.feedOffset);
      if (!this.mounted || generation !== this.generation) return;
      const added: DynamicItem[] = [];
      for (const item of page.items || []) { if (item.id_str && !this.ids.has(item.id_str)) { this.ids.add(item.id_str); added.push(item); } }
      this.source.append(added); this.count = this.source.totalCount(); this.hasMore = page.has_more && page.offset !== this.feedOffset && added.length > 0; this.feedOffset = page.offset;
    } catch (error) { if (this.mounted && generation === this.generation) this.errorText = (error as Error).message; }
    finally { if (this.mounted && generation === this.generation) this.busy = false; }
  }
  private images(item: DynamicItem): string[] {
    const major = item.modules?.module_dynamic?.major;
    const pictures = major?.opus?.pics || major?.draw?.items || [];
    const images: string[] = [];
    for (const picture of pictures) { const image = picture.url || picture.src || ''; if (image) images.push(image.startsWith('//') ? 'https:' + image : image.replace('http:', 'https:')); }
    return images;
  }
  private text(item: DynamicItem): string {
    const body = item.modules?.module_dynamic; const opus = body?.major?.opus;
    return (opus?.title ? opus.title + '\n' : '') + (opus?.summary?.text || body?.desc?.text || '');
  }
  private toggleDynamic(id: string): void {
    if (this.collapsedDynamicIds.includes(id)) this.collapsedDynamicIds = this.collapsedDynamicIds.filter((value: string) => value !== id);
    else this.collapsedDynamicIds = [...this.collapsedDynamicIds, id];
  }
  @Builder
  content(item: DynamicItem, depth: number) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Image(item.modules.module_author.face).width(36).height(36).borderRadius(18)
        Column({ space: 4 }) {
          Text(item.modules.module_author.name).fontSize(15).fontWeight(FontWeight.Medium)
          Text(item.modules.module_author.pub_time).fontSize(11).fontColor('#888888')
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').onClick(() => { this.onCreator(item.modules.module_author.mid); })
      if (depth === 0 && this.collapsedDynamicIds.includes(item.id_str)) {
        Text(this.text(item) || item.modules.module_dynamic.major?.archive?.title || '查看完整动态').fontSize(14).fontColor('#777777').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
      if (this.text(item)) { Text(this.text(item)).fontSize(15).width('100%').maxLines(12) }
      if (item.modules.module_dynamic.major?.archive) {
        Column({ space: 8 }) {
          Image(item.modules.module_dynamic.major.archive.cover).width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Cover).borderRadius(10)
          Text(item.modules.module_dynamic.major.archive.title).fontSize(15).maxLines(2).width('100%')
        }.onClick(() => {
          const archive = item.modules.module_dynamic.major!.archive!;
          this.onVideo({ aid: Number(archive.aid), bvid: archive.bvid, title: archive.title, pic: archive.cover, duration: archive.duration_text || 0, preview: archive.preview });
        })
      }
      if (this.images(item).length) {
        Grid() {
          ForEach(this.images(item).slice(0, 9), (image: string) => {
            GridItem() { Image(/^https:\/\/[^/]*hdslb\.com\//.test(image) && !image.includes('@') ? image + '@320w_320h_1c.webp' : image).width('100%').height(100).objectFit(ImageFit.Cover).borderRadius(8).onClick(() => { this.onImages(this.images(item)); }) }
          }, (image: string) => image)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(6).rowsGap(6).height(Math.ceil(Math.min(9, this.images(item).length) / 3) * 106).width('100%')
      }
      if (item.orig && depth < 3) { this.content(item.orig, depth + 1) }
      else if (item.type === 'DYNAMIC_TYPE_FORWARD') { Text('原动态已删除、不可见或超过展示层数').fontSize(13).fontColor('#888888') }
      }
      if (depth === 0) {
        Row() {
          Button({ type: ButtonType.Capsule }) {
            Row({ space: 4 }) {
              Text(this.collapsedDynamicIds.includes(item.id_str) ? '展开' : '收起').fontSize(13).fontColor('#D8353F')
              SymbolGlyph(this.collapsedDynamicIds.includes(item.id_str) ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up')).fontSize(12).fontColor(['#D8353F'])
            }
          }.height(36).backgroundColor(Color.Transparent).padding({ left: 0, right: 10 }).onClick(() => { this.toggleDynamic(item.id_str); })
          Blank()
        }.width('100%')
      }
    }.padding(16).backgroundColor(depth > 0 ? '#F7F7F7' : '#FFFFFF').width('100%')
  }
  @Builder
  item(item: DynamicItem) { this.content(item, 0) }
  build() {
    Column() {
      Row({ space: 10 }) { Text('动态').fontSize(24).fontWeight(FontWeight.Bold); if (this.account?.demo) { Text('演示数据').fontSize(12).fontColor('#D8353F').padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor('#FFF0F2').borderRadius(12) } }.width('100%').padding(16)
      if (!this.account) {
        Column({ space: 16 }) { Text('登录后查看关注动态').fontColor('#777777'); Button('登录 B站').onClick(this.onLogin) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          LazyForEach(this.source, (item: DynamicItem) => { ListItem() { this.item(item) } }, (item: DynamicItem) => item.id_str)
          ListItem() {
            Column({ space: 8 }) {
              Text(this.errorText).fontSize(13).fontColor('#888888')
              if (this.busy) { LoadingProgress().width(28).height(28) }
              else if (this.errorText) { Button('重试').onClick(() => { this.load(); }) }
              else { Text(this.hasMore ? '上拉加载更多' : this.count === 0 ? '暂时没有动态' : '已经到底了').fontSize(13).fontColor('#888888') }
            }.width('100%').padding({ bottom: 130, top: 12 })
          }
        }.layoutWeight(1).cachedCount(2).onReachEnd(() => { if (this.count && !this.errorText) this.load(); })
      }
    }.height('100%').backgroundColor('#F7F7F7')
  }
}
