import { HdsNavigation, HdsTabs, HdsTabsController, HdsTabsFloatingStyle, hdsMaterial } from '@kit.UIDesignKit';

import { BiliClient, Video, VideoPart, Account, FavoriteFolder, Creator } from '../services/BiliClient';
import { TelevisionClient, CommandPayload, QueueItem } from '../services/TelevisionClient';
import { preferences } from '@kit.ArkData';
import { SearchPane } from '../components/SearchPane';
import { VideoFeed } from '../components/VideoFeed';
import { TelevisionPlayer } from '../components/TelevisionPlayer';
import { LoginPane, MyPane, FavoriteFoldersPane, CreatorsPane } from '../components/AccountPages';
import { DynamicsPane } from '../components/DynamicsPane';
import { AboutPane } from '../components/AboutPane';
import { LegalDocumentPane } from '../components/LegalDocumentPane';
import { TelevisionDiscovery, DiscoveredTelevision } from '../services/TelevisionDiscovery';
import { sharedVideo } from '../services/SharedVideo';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

interface SharedVideoPayload { id: string; text: string }

@Entry
@Component
struct Index {
  @State selectedTab: number = 0;
  private tabController: HdsTabsController = new HdsTabsController();
  private floatingStyle: HdsTabsFloatingStyle = {
    // The window already avoids the system indicator; this is additional breathing room.
    barBottomMargin: 16,
    systemMaterialEffect: {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    },
    lightColor: '#1FD8353F'
  };
  private discovery: TelevisionDiscovery = new TelevisionDiscovery();
  @State nearbyTelevisions: DiscoveredTelevision[] = [];
  @State searching: boolean = false;
  @State discoveryMessage: string = '';
  @State volumeFeedbackVisible: boolean = false;
  @State volumeFeedbackValue: number = 0;
  private volumeFeedbackTimer: number = -1;
  private lastShareId: string = '';
  private shareGeneration: number = 0;
  private readonly volumeKeyListener = (direction: number): void => { if (this.consent) this.television.adjustVolume(direction); };
  private readonly foregroundListener = (foreground: boolean): void => { this.television.setForeground(foreground); if (!foreground) { clearTimeout(this.volumeFeedbackTimer); this.volumeFeedbackVisible = false; } };
  private readonly shareListener = (share: SharedVideoPayload): void => { this.receiveShare(share); };
  private api: BiliClient = new BiliClient();
  private television: TelevisionClient = new TelevisionClient();
  @State consent: boolean = false;
  @State consentDocument: string = '';
  @State account: Account | undefined = undefined;
  @State visitedDynamics: boolean = false;
  private pendingAccountSection: string = '';
  @State errorText: string = '';
  @State screen: string = 'home';
  private paths: NavPathStack = new NavPathStack();
  private playerBackHandler: () => boolean = () => false;
  @State details: Video | undefined = undefined;
  @State address: string = '192.168.5.228:9838';
  @State connected: boolean = false;
  @State televisionName: string = '';
  @State savedAddress: string = '';
  @State hasSavedTelevision: boolean = false;
  @State reconnectEnabled: boolean = false;
  @State manualIp: string = '';
  @State manualPort: string = '';
  private connectionFormStore?: preferences.Preferences;

  @State connecting: boolean = false;
  private detailGeneration: number = 0;
  private loadGeneration: number = 0;
  private pendingVideo: Video | undefined = undefined;
  @State visitedPopular: boolean = false;

  async aboutToAppear(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.eventHub.on('television-volume-key', this.volumeKeyListener);
    context.eventHub.on('foreground', this.foregroundListener);
    context.eventHub.on('shared-video', this.shareListener);
    this.television.onHardwareAvailability = (enabled: boolean) => { context.eventHub.emit('remote-connected', enabled && this.consent); };
    this.television.onHardwareVolume = (value: number) => {
      this.volumeFeedbackValue = value; this.volumeFeedbackVisible = true; clearTimeout(this.volumeFeedbackTimer);
      this.volumeFeedbackTimer = setTimeout(() => { this.volumeFeedbackVisible = false; }, 1400);
    };
    this.api.onAccountChanged = () => { this.account = this.api.account; };
    this.television.onChange = () => {
      this.connected = this.television.connected; this.televisionName = this.television.name;
      this.savedAddress = this.television.address; this.hasSavedTelevision = this.television.hasSavedTelevision; this.reconnectEnabled = this.television.reconnectEnabled;
      if (this.connected) this.continuePendingVideo();
    };
    this.television.onError = (message: string) => { this.errorText = message; };
    try {
      const store = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'native_settings' });
      const accepted = await store.get('consent', false) as boolean && await store.get('policyVersion', '') === '1.0.2-native';
      if (accepted) await this.api.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.consent = accepted;
      if (accepted) { await this.television.initialize(context); context.eventHub.emit('pull-share'); }
      this.connectionFormStore = store;
      this.address = this.television.address || await store.get('televisionAddress', this.address) as string;
      this.manualIp = await store.get('manualIp', this.television.address.split(':')[0] || '') as string;
      this.manualPort = await store.get('manualPort', this.television.address.split(':')[1] || '') as string;
    } catch (error) { this.errorText = '无法读取本地设置，请重试'; }
  }
  aboutToDisappear(): void {
    ++this.shareGeneration; this.television.dispose(); this.discovery.stop(); clearTimeout(this.volumeFeedbackTimer);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.eventHub.emit('remote-connected', false); context.eventHub.off('television-volume-key', this.volumeKeyListener);
    context.eventHub.off('foreground', this.foregroundListener); context.eventHub.off('shared-video', this.shareListener);
  }
  private async acceptConsent(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'native_settings' });
      await store.put('consent', true); await store.put('policyVersion', '1.0.2-native'); await store.flush(); await this.api.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); this.consent = true;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext; await this.television.initialize(context); context.eventHub.emit('pull-share');
    } catch (error) { this.errorText = '无法保存选择，请重试'; }
  }
  private async openVideo(video: Video): Promise<void> {
    const generation = ++this.detailGeneration;
    this.openPage('detail'); this.details = undefined; this.errorText = '';
    try { const detail = await this.api.detail(video.aid); if (generation === this.detailGeneration && this.screen === 'detail') this.details = detail; }
    catch (error) { if (generation === this.detailGeneration && this.screen === 'detail') this.errorText = (error as Error).message; }
  }
  private saveManualConnection(): void {
    this.connectionFormStore?.put('manualIp', this.manualIp);
    this.connectionFormStore?.put('manualPort', this.manualPort);
    this.connectionFormStore?.flush();
  }
  private continuePendingVideo(): void {
    if (!this.connected || !this.pendingVideo) return;
    const video = this.pendingVideo; this.pendingVideo = undefined;
    this.playVideo(video);
  }
  private async connectTelevision(deviceAddress?: string): Promise<void> {
    this.discovery.stop(); this.searching = false; this.connecting = true; this.errorText = '';
    try {
      const portText = this.manualPort.trim();
      if (!deviceAddress && portText && (!/^\d+$/.test(portText) || Number(portText) < 1 || Number(portText) > 65535)) throw new Error('端口必须是 1–65535 的数字');
      this.address = deviceAddress || `${this.manualIp.trim() || '192.168.5.228'}:${portText || '9838'}`;
      await this.television.connect(this.address);
      const store = this.connectionFormStore || await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'native_settings' });
      await store.put('televisionAddress', this.address); await store.flush();
      this.continuePendingVideo();
      if (this.screen === 'connection') this.closePage();
    } catch (error) { this.errorText = (error as Error).message; }
    finally { this.connecting = false; }
  }
  private async sendCommand(action: string, payload: CommandPayload = {}): Promise<void> {
    try { await this.television.command(action, payload); }
    catch (error) { this.errorText = (error as Error).message; this.television.onError(this.errorText); }
  }
  private async playVideo(video: Video): Promise<void> {
    if (video.preview) { this.openVideo(video); return; }
    if (!this.connected) { this.pendingVideo = video; this.openPage('connection'); return; }
    const generation = ++this.loadGeneration;
    // Open the existing placeholder first; request completion does not gate page navigation.
    this.openPage('player');
    setTimeout(() => { if (generation === this.loadGeneration) this.television.onActivity('正在获取视频…'); }, 0);
    try {
      if (video.epid || video.seasonId) { await this.television.command('load', { aid: 0, cid: 0, epid: video.epid, seasonId: video.seasonId, positionMs: video.historyPositionMs || 0 }); if (generation === this.loadGeneration) this.television.onActivity(''); return; }
      const details = await this.api.detail(video.aid);
      if (generation !== this.loadGeneration || !this.connected) return;
      const resumeCid = video.historyCid || details.historyCid;
      const part = details.pages?.find((item: VideoPart) => item.cid === resumeCid) || details.pages?.[0];
      if (!part) throw new Error('当前视频没有可播放的分 P');
      await this.television.command('load', { aid: details.aid, bvid: details.bvid, cid: part.cid, title: details.title, positionMs: (part.cid === resumeCid ? (video.historyPositionMs === undefined ? details.historyPositionMs || 0 : video.historyPositionMs) : 0),
        queue: (details.pages || []).map((item: VideoPart): QueueItem => { return { aid: details.aid, bvid: details.bvid, cid: item.cid, title: item.part }; }) });
      if (generation === this.loadGeneration) this.television.onActivity('');
    } catch (error) {
      if (generation === this.loadGeneration) this.television.onError((error as Error).message);
    }
  }
  private async playPart(cid: number): Promise<void> {
    if (!this.connected) { this.openPage('connection'); return; }
    const video = this.details; if (!video) return;
    if (video.preview) { this.getUIContext().getPromptAction().showToast({ message: '演示视频仅用于查看页面' }); return; }
    this.openPage('player');
    await this.sendCommand('load', { aid: video.aid, bvid: video.bvid, cid: cid, title: video.title,
      queue: (video.pages || []).map((part: VideoPart): QueueItem => { return { aid: video.aid, bvid: video.bvid, cid: part.cid, title: part.part }; }) });
  }
  private async applyWindowStyle(player: boolean): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext);
      await mainWindow.setWindowSystemBarProperties({ statusBarColor: player ? '#15161C' : '#F7F7F7', statusBarContentColor: player ? '#FFFFFF' : '#191919', navigationBarColor: '#FFFFFF', navigationBarContentColor: '#191919' });
    } catch (error) { /* A closing window cannot prevent navigation. */ }
  }
  private openPage(name: string, param?: Object): void { this.screen = name; if (name === 'player' && this.paths.getAllPathName().includes('player')) this.paths.popToName('player'); else this.paths.pushPath({ name: name, param: param }); if (name === 'connection') this.searchTelevisions(); }
  private closePage(): void { if (this.screen === 'connection') { this.pendingVideo = undefined; this.discovery.stop(); this.searching = false; } if (this.screen === 'player') ++this.loadGeneration; this.paths.pop(); this.screen = this.paths.size() > 0 ? this.paths.getAllPathName()[this.paths.size() - 1] : 'home'; this.errorText = ''; this.applyWindowStyle(this.screen === 'player'); }
  @Builder
  destination(name: string, param: Object) {
    NavDestination() {
      if (name === 'detail') { this.detailsPage() }
      else if (name === 'connection') { this.connectionPage() }
      else if (name === 'login') {
        LoginPane({ api: this.api, onComplete: () => { this.closePage(); const section = this.pendingAccountSection; this.pendingAccountSection = ''; if (section) this.openAccountSection(section); } })
      } else if (name === 'favorites') {
        FavoriteFoldersPane({ api: this.api, onOpen: (folder: FavoriteFolder) => { this.openPage('folder', folder); } })
      } else if (name === 'folder') {
        VideoFeed({ api: this.api, mode: 'favorite:' + (param as FavoriteFolder).id, onOpen: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } })
      } else if (name === 'history') {
        VideoFeed({ api: this.api, mode: 'history', onOpen: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } })
      } else if (name === 'followings') {
        CreatorsPane({ api: this.api, onOpen: (creator: Creator) => { this.openCreator(creator.mid); } })
      } else if (name.startsWith('creator:')) {
        VideoFeed({ api: this.api, mode: name, onOpen: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } })
      } else if (name === 'images') {
        Swiper() { ForEach(param as string[], (image: string) => { Image(image).width('100%').height('100%').objectFit(ImageFit.Contain) }, (image: string) => image) }.width('100%').height('100%').cachedCount(1).backgroundColor('#15161C')
      } else if (name === 'about') {
        AboutPane({ api: this.api, onWithdraw: () => { this.withdrawConsent(); }, onLegal: (document: string) => { this.openPage('legal', document); } })
      }
      else if (name === 'legal') { LegalDocumentPane({ document: param as string }) }
      else if (name === 'search') {
        SearchPane({ api: this.api, onLogin: () => { this.openPage('login'); }, onVideo: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } })
      } else if (name === 'player') {
        TelevisionPlayer({ television: this.television, visible: this.screen === 'player', onClose: () => { this.closePage(); }, onConnection: () => { this.openPage('connection'); },
          registerBackHandler: (handler: () => boolean) => { this.playerBackHandler = handler; } })
      }
    }.hideTitleBar(name === 'player').title(name === 'legal' ? ((param as string) === 'terms' ? '用户协议' : (param as string) === 'notice' ? '开源说明' : (param as string) === 'license' ? 'GPL-3.0' : '隐私政策') : name === 'detail' ? '视频详情' : name === 'connection' ? '连接电视' : name === 'search' ? '搜索' : name === 'login' ? '登录 B站' : name === 'favorites' ? '我的收藏' : name === 'folder' ? (param as FavoriteFolder).title : name === 'history' ? '观看记录' : name === 'followings' ? '我的关注' : name === 'images' ? '图片' : name === 'about' ? '关于与隐私' : name.startsWith('creator:') ? 'UP主空间' : '电视播放').onShown(() => { this.screen = name; this.applyWindowStyle(name === 'player'); })
      .onBackPressed(() => { if (name === 'player' && this.playerBackHandler()) return true; if (name === 'player') ++this.loadGeneration; if (name === 'connection') { this.pendingVideo = undefined; this.discovery.stop(); this.searching = false; } this.screen = 'home'; this.applyWindowStyle(false); return false; })
  }
  @Builder
  tabItem(index: number, label: string, symbol: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol).fontSize(22).fontColor([this.selectedTab === index ? '#D8353F' : '#777777'])
      Text(label).fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.selectedTab === index ? '#D8353F' : '#777777')
    }.width('100%').height('100%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
  }
  @Builder
  home() {
    Column() {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) { SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor(['#888888']); Text('搜索视频、UP主').fontSize(15).fontColor('#888888'); Blank() }.width('100%').padding({ left: 14, right: 14 })
        }.height(40).layoutWeight(1).backgroundColor('#EEEEEF').borderRadius(22).onClick(() => { this.openPage('search'); })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.person')).fontSize(22).fontColor(['#555555'])
        }.width(36).height(36).backgroundColor('#EEEEEF').onClick(() => { this.tabController.changeIndex(2); })
      }.padding({ left: 14, right: 14, top: 8, bottom: 4 })
      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() { VideoFeed({ api: this.api, mode: 'recommended', onOpen: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } }) }.tabBar(SubTabBarStyle.of('推荐').labelStyle({ selectedColor: '#D8353F', unselectedColor: '#666666' }).indicator({ color: '#D8353F' }))
        TabContent() { if (this.visitedPopular) { VideoFeed({ api: this.api, mode: 'popular', onOpen: (video: Video) => { this.playVideo(video); }, onDetails: (video: Video) => { this.openVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); } }) } }.tabBar(SubTabBarStyle.of('热门').labelStyle({ selectedColor: '#D8353F', unselectedColor: '#666666' }).indicator({ color: '#D8353F' }))
      }.barHeight(56).barMode(BarMode.Fixed).onChange((index: number) => { if (index === 1) this.visitedPopular = true; }).layoutWeight(1)
    }.height('100%').backgroundColor('#FFFFFF')
  }
  private openCreator(mid: number): void { if (mid > 0) this.openPage('creator:' + mid); }
  private openAccountSection(section: string): void {
    if (section === 'exitDemo') { this.api.exitDemo(); return; }
    if (['favorites', 'history', 'followings', 'mySpace'].includes(section) && !this.account) {
      this.pendingAccountSection = section; this.openPage('login'); return;
    }
    if (section === 'mySpace') { this.openCreator(this.account!.mid); return; }
    if (section === 'logout') {
      this.getUIContext().showAlertDialog({ title: '退出登录？', message: '电视使用自己的账号，退出手机账号后电视可继续播放。',
        primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '退出登录', action: () => { this.api.logout(); } } }); return;
    }
    this.openPage(section);
  }
  private async withdrawConsent(): Promise<void> {
    ++this.loadGeneration; ++this.detailGeneration; this.pendingVideo = undefined; this.discovery.stop(); await this.television.clearSaved();
    await this.api.logout(); await this.api.clearSearchHistory();
    const store = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'native_settings' });
    await store.clear(); await store.flush(); this.paths.clear(); this.screen = 'home'; this.consent = false;
  }
  @Builder
  detailsPage() {
    Column() {
      if (this.details) {
        Scroll() {
          Column({ space: 16 }) {
            Image(this.details.pic).width('100%').aspectRatio(16 / 9).borderRadius(12)
            Text(this.details.title).fontSize(20).fontWeight(FontWeight.Medium).width('100%')
            Text(this.details.owner?.name || '').fontSize(14).fontColor('#777777').width('100%')
            Text(this.details.preview ? '演示视频 · 仅预览详情' : '选集 · 在电视上播放').fontSize(16).width('100%')
            ForEach(this.details.pages || [], (part: VideoPart) => {
              Button(part.part).enabled(!this.details?.preview).width('100%').fontColor('#D8353F').backgroundColor('#FFF1F2').onClick(() => { this.playPart(part.cid); })
            })
            Text(this.details.desc || '').fontSize(14).fontColor('#777777').width('100%')
          }.padding(16)
        }.align(Alignment.TopStart).layoutWeight(1)
      } else if (!this.errorText) { LoadingProgress().width(36).height(36) }
      Text(this.errorText).fontColor('#D8353F').padding(12)
    }.height('100%')
  }
  @Builder
  connectionPage() {
    Scroll() {
      Column({ space: 0 }) {
        Text('打开电视上的跃映，并让手机与电视连接同一局域网。选择电视即可连接，无需配对码。')
          .fontSize(14).fontColor('#555555').lineHeight(22).width('100%')
        if (this.hasSavedTelevision) {
          Text('我的电视').fontSize(17).fontWeight(FontWeight.Medium).width('100%').margin({ top: 24, bottom: 8 })
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.smartscreen')).fontSize(26).fontColor([this.connected ? '#D8353F' : '#777777'])
            Column({ space: 5 }) {
              Text(this.televisionName || '我的电视').fontSize(16).fontWeight(FontWeight.Medium)
              Text(this.connected ? '已连接' : this.connecting ? '正在连接…' : this.reconnectEnabled ? '等待电视上线 · 会自动重连' : '已保存 · 点按连接')
                .fontSize(13).fontColor(this.connected ? '#278654' : '#777777')
              Text(this.savedAddress).fontSize(13).fontColor('#777777')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.connecting) { LoadingProgress().width(22).height(22) }
            else { SymbolGlyph(this.connected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.chevron_right')).fontSize(22).fontColor([this.connected ? '#D8353F' : '#777777']) }
          }.padding(16).width('100%').borderRadius(20).backgroundColor('#FFFFFF')
            .enabled(!this.connecting).onClick(() => { this.connectTelevision(this.savedAddress); })
        }
        Row() {
          Text('新发现设备').fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button('重新搜索').fontSize(14).fontColor('#D8353F').backgroundColor(Color.Transparent).enabled(!this.searching)
            .onClick(() => { this.searchTelevisions(); })
        }.width('100%').margin({ top: 20 })
        if (this.searching) { Progress({ value: 35, total: 100, type: ProgressType.Linear }).width('100%').color('#D8353F').style({ enableScanEffect: true }).margin({ bottom: 8 }) }
        if (!this.connected && this.nearbyTelevisions.filter((device: DiscoveredTelevision) => device.address !== this.savedAddress).length === 0) {
          Text('自动搜索未找到时，可手动输入电视地址。').fontSize(13).fontColor('#777777').width('100%').margin({ top: 8 })
        }
        ForEach(this.nearbyTelevisions, (device: DiscoveredTelevision) => {
          if (device.address !== this.savedAddress) {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.smartscreen')).fontSize(24).fontColor(['#777777'])
              Column({ space: 6 }) { Text(device.name).fontSize(16); Text(device.address).fontSize(13).fontColor('#777777') }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor(['#888888'])
            }.padding({ top: 16, bottom: 16 }).width('100%').enabled(!this.connecting)
              .onClick(() => { this.connectTelevision(device.address); })
          }
        }, (device: DiscoveredTelevision) => device.deviceId)
        Text(this.discoveryMessage || '暂未发现新设备，仍可手动输入电视地址。').fontSize(13).fontColor('#777777').lineHeight(20).width('100%').margin({ top: 12, bottom: 12 })
        Text('手动连接').fontSize(17).fontWeight(FontWeight.Medium).width('100%').margin({ top: 20, bottom: 12 })
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text('电视 IP 地址').fontSize(12).fontColor('#777777').width('100%')
            TextInput({ text: this.manualIp, placeholder: '192.168.5.228' }).type(InputType.URL).height(48)
              .onChange((value: string) => { this.manualIp = value; this.saveManualConnection(); })
          }.layoutWeight(1)
          Column({ space: 6 }) {
            Text('端口').fontSize(12).fontColor('#777777').width('100%')
            TextInput({ text: this.manualPort, placeholder: '9838' }).type(InputType.Number).maxLength(5).height(48)
              .onChange((value: string) => { this.manualPort = value; this.saveManualConnection(); })
          }.width(100)
        }.width('100%')
        Text('留空时连接 192.168.5.228:9838；输入内容会自动保存。').fontSize(12).fontColor('#777777').lineHeight(20).width('100%').margin({ top: 12 })
        Button(this.connecting ? '正在连接…' : '连接电视').height(48).width('100%').fontSize(16).fontColor('#FFFFFF').backgroundColor('#D8353F')
          .enabled(!this.connecting).onClick(() => { this.connectTelevision(); }).margin({ top: 20 })
        if (this.errorText) { Text(this.errorText).fontSize(13).fontColor('#D8353F').width('100%').margin({ top: 16 }) }
        Text('连接成功后会记住电视。电视的 B站账号在电视内扫码登录，手机只发送视频编号。').fontSize(13).fontColor('#777777').lineHeight(21).width('100%').margin({ top: 16 })
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
    }.align(Alignment.TopStart).width('100%').height('100%').backgroundColor('#F7F7F7')
  }
  private searchTelevisions(): void {
    if (!this.consent) return;
    this.nearbyTelevisions = []; this.searching = true; this.discoveryMessage = '正在搜索同一局域网内的电视…';
    this.discovery.onDevice = (device: DiscoveredTelevision) => {
      if (this.screen !== 'connection') return;
      const existing = this.nearbyTelevisions.findIndex((item: DiscoveredTelevision) => item.deviceId === device.deviceId);
      if (existing >= 0) { const devices = this.nearbyTelevisions.slice(); devices[existing] = device; this.nearbyTelevisions = devices; }
      else this.nearbyTelevisions = this.nearbyTelevisions.concat([device]);
      this.discoveryMessage = this.connected ? '电视已在线，继续搜索其他设备…' : '发现电视，正在连接';
      if (!this.connected && !this.connecting) { this.connectTelevision(device.address); }
    };
    this.discovery.onComplete = () => { this.searching = false; this.discoveryMessage = this.nearbyTelevisions.some((device: DiscoveredTelevision) => device.address !== this.savedAddress) ? '选择电视即可连接' : '暂未发现新设备，仍可手动输入电视地址。'; };
    this.discovery.search([this.address, '192.168.5.228:9838']);
  }
  private async receiveShare(share: SharedVideoPayload): Promise<void> {
    if (!this.consent || !share?.id || share.id === this.lastShareId) return;
    this.lastShareId = share.id; const generation = ++this.shareGeneration;
    try {
      const video = await sharedVideo(share.text, this.api);
      if (generation !== this.shareGeneration || !this.consent) return;
      (this.getUIContext().getHostContext() as common.UIAbilityContext).eventHub.emit('acknowledge-share', share.id);
      this.playVideo(video);
    } catch (error) {
      if (generation === this.shareGeneration) this.getUIContext().getPromptAction().showToast({ message: (error as Error).message });
      this.lastShareId = '';
    }
  }
  @Builder
  volumeFeedback() {
    Column() {
    if (this.volumeFeedbackVisible) {
      Column({ space: 8 }) {
        Row() { Text('电视音量').fontSize(14).fontColor('#FFFFFF'); Blank(); Text(`${this.volumeFeedbackValue}%`).fontSize(14).fontColor('#FFFFFF') }.width('100%')
        Progress({ value: this.volumeFeedbackValue, total: 100 }).color('#EF6B75').width('100%')
      }.padding(16).width(260).margin({ top: 16 }).backgroundColor('#292A30').borderRadius(18)
    }
    }.hitTestBehavior(HitTestMode.None)
  }
  build() {
    if (!this.consent) {
      if (this.consentDocument) {
        Column() {
          Row() {
            Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor(['#333333']) }.width(44).height(44).backgroundColor(Color.Transparent).onClick(() => { this.consentDocument = ''; })
            Text(this.consentDocument === 'terms' ? '用户协议' : '隐私政策').fontSize(22).fontWeight(FontWeight.Medium)
          }.width('100%').padding(12)
          LegalDocumentPane({ document: this.consentDocument }).layoutWeight(1)
        }.height('100%').width('100%')
      } else {
      Column({ space: 24 }) {
        Text('欢迎使用跃映').fontSize(28).fontWeight(FontWeight.Bold)
        Text('在手机选片，在电视上观看').fontSize(16).fontColor('#777777')
        Text('同意后，浏览和搜索会访问 B站服务；连接电视会访问你指定的局域网地址并同步播放状态。可选扫码登录后，登录凭据、搜索历史和电视地址保存在本机应用私有目录。手机不播放视频，也不向电视发送 B站登录凭据。').fontSize(16).lineHeight(26)
        Text('本项目基于 PiliPlus / NeoBV 二次开发，保留原作者权益。当前浏览代码按 GPL-3.0 提供源码。').fontSize(13).fontColor('#777777')
        Row({ space: 12 }) {
          Button('隐私政策').fontColor('#D8353F').backgroundColor(Color.Transparent).onClick(() => { this.consentDocument = 'privacy'; })
          Button('用户协议').fontColor('#D8353F').backgroundColor(Color.Transparent).onClick(() => { this.consentDocument = 'terms'; })
        }
        Button('同意隐私政策及用户协议并继续').backgroundColor('#D8353F').onClick(() => { this.acceptConsent(); })
        Button('不同意并退出').fontColor('#777777').backgroundColor(Color.Transparent).onClick(() => { (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf(); })
        Text(this.errorText).fontColor('#D8353F')
      }.padding(24).height('100%').justifyContent(FlexAlign.Center)
      }
    } else {
      HdsNavigation(this.paths) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        HdsTabs({ controller: this.tabController }) {
          TabContent() { this.home() }.tabBar(this.tabItem(0, '首页', $r('sys.symbol.house')))
          TabContent() { if (this.visitedDynamics) { DynamicsPane({ api: this.api, account: this.account, onLogin: () => { this.openPage('login'); }, onVideo: (video: Video) => { this.playVideo(video); }, onCreator: (mid: number) => { this.openCreator(mid); }, onImages: (images: string[]) => { this.openPage('images', images); } }) } }.tabBar(this.tabItem(1, '动态', $r('sys.symbol.heart')))
          TabContent() { MyPane({ account: this.account, onOpen: (section: string) => { this.openAccountSection(section); } }) }.tabBar(this.tabItem(2, '我的', $r('sys.symbol.person')))
        }.barPosition(BarPosition.End).barMode(BarMode.Fixed).barOverlap(true).barFloatingStyle(this.floatingStyle).backgroundColor('#FFFFFF').onChange((index: number) => { this.selectedTab = index; if (index === 1) this.visitedDynamics = true; })
        Button(this.connected ? '电视播放' : '连接电视').fontSize(14).fontColor('#D8353F').backgroundColor('#FFF1F2').height(44)
          .padding({ left: 20, right: 20 }).margin({ right: 16, bottom: 96 })
          .onClick(() => { this.openPage(this.connected ? 'player' : 'connection'); this.errorText = ''; })
      }.height('100%')
      }.mode(NavigationMode.Stack).hideTitleBar(true).navDestination(this.destination).width('100%').height('100%').overlay(this.volumeFeedback(), { align: Alignment.Top })
    }
  }
}
