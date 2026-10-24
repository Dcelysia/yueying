import { BiliClient, Video, Creator } from '../services/BiliClient';
import { CreatorsPane } from './AccountPages';
import { VideoFeed } from './VideoFeed';
@Component
export struct SearchPane {
  api: BiliClient = new BiliClient();
  onLogin: () => void = () => {};
  onVideo: (video: Video) => void = () => {};
  onDetails: (video: Video) => void = () => {};
  onCreator: (mid: number) => void = () => {};
  @State keyword: string = '';
  @State committed: string = '';
  @State visitedCreators: boolean = false;
  @State history: string[] = [];
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; this.api.searchHistory().then((items: string[]) => { if (this.active) this.history = items; }); }
  aboutToDisappear(): void { this.active = false; }
  private submit(keyword: string): void {
    const value = keyword.trim(); if (!value) return;
    this.keyword = value; this.visitedCreators = false; this.committed = value;
    this.api.rememberSearch(value).then(() => this.api.searchHistory()).then((items: string[]) => { if (this.active) this.history = items; });
  }
  build() {
    Column({ space: 12 }) {
      Search({ value: this.keyword, placeholder: '搜索视频、UP主' }).searchButton('搜索')
        .onChange((value: string) => { this.keyword = value; }).onSubmit((value: string) => { this.submit(value); }).margin({ left: 16, right: 16 }).height(44)
      if (this.committed) {
        ForEach([this.committed], (keyword: string) => {
          Tabs({ barPosition: BarPosition.Start }) {
          TabContent() { VideoFeed({ api: this.api, mode: 'search', keyword: keyword, onLogin: this.onLogin, onOpen: this.onVideo, onDetails: this.onDetails, onCreator: this.onCreator }) }.tabBar(SubTabBarStyle.of('视频').labelStyle({ selectedColor: '#D8353F' }).indicator({ color: '#D8353F' }))
          TabContent() { if (this.visitedCreators) { CreatorsPane({ api: this.api, mode: 'search', keyword: keyword, onLogin: this.onLogin, onOpen: (creator: Creator) => { this.onCreator(creator.mid); } }) } }.tabBar(SubTabBarStyle.of('UP主').labelStyle({ selectedColor: '#D8353F' }).indicator({ color: '#D8353F' }))
          }.barHeight(56).onChange((index: number) => { if (index === 1) this.visitedCreators = true; }).layoutWeight(1)
        }, (keyword: string) => keyword)
      } else {
        Row() { Text('搜索历史').fontSize(17).fontWeight(FontWeight.Medium); Blank(); Button('清除').fontSize(13).backgroundColor(Color.Transparent).fontColor('#888888').onClick(() => { this.api.clearSearchHistory(); this.history = []; }) }.width('100%').padding({ left: 16, right: 16 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.history, (keyword: string) => {
            Button(keyword).fontSize(14).fontColor('#555555').backgroundColor('#F2F2F2').height(36).borderRadius(18).margin(4).onClick(() => { this.submit(keyword); })
          }, (keyword: string) => keyword)
        }.width('100%').padding({ left: 12, right: 12 })
        if (!this.history.length) { Text('输入关键词查找视频').fontSize(14).fontColor('#888888').margin({ top: 32 }) }
      }
    }.padding({ top: 12 }).height('100%')
  }
}
