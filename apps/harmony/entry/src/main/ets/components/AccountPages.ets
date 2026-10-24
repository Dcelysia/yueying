import { common } from '@kit.AbilityKit';
import { PagedItems } from './PagedItems';
import { BiliClient, Account, FavoriteFolder, Creator } from '../services/BiliClient';

@Component
export struct LoginPane {
  api: BiliClient = new BiliClient();
  onComplete: () => void = () => {};
  @State qrUrl: string = '';
  @State message: string = '正在生成登录二维码…';
  @State busy: boolean = false;
  @State verifying: boolean = false;
  @State needsVerification: boolean = false;
  @State canRetry: boolean = false;
  private generation: number = 0;
  private timer: number = -1;
  private active: boolean = false;
  private foreground: boolean = true;
  private polling: boolean = false;
  private qrKey: string = '';
  private expiresAt: number = 0;
  private failures: number = 0;
  private readonly foregroundListener = (foreground: boolean): void => {
    this.foreground = foreground; clearTimeout(this.timer);
    if (!foreground || !this.active) return;
    if (this.api.account) this.onComplete();
    else if (this.api.hasLoginCredentials) this.verifySavedLogin();
    else if (this.qrKey) this.poll(this.generation);
  };
  aboutToAppear(): void {
    this.active = true;
    (this.getUIContext().getHostContext() as common.UIAbilityContext).eventHub.on('foreground', this.foregroundListener);
    this.api.onLoginProgress = (message: string) => { if (this.active) this.message = message; };
    if (this.api.hasLoginCredentials) { this.needsVerification = true; this.verifySavedLogin(); }
    else this.generate();
  }
  aboutToDisappear(): void {
    this.active = false; ++this.generation; clearTimeout(this.timer); this.api.onLoginProgress = () => {};
    (this.getUIContext().getHostContext() as common.UIAbilityContext).eventHub.off('foreground', this.foregroundListener);
  }
  private safeError(error: Error): string {
    return /https?:\/\/|qrcode_key|SESSDATA|bili_jct/i.test(error.message) ? '网络请求失败，请检查网络后重试' : error.message || '登录请求失败，请重试';
  }
  private async generate(): Promise<void> {
    if (this.busy || this.verifying) return;
    const generation = ++this.generation; clearTimeout(this.timer); this.busy = true;
    this.qrUrl = ''; this.qrKey = ''; this.failures = 0; this.needsVerification = false; this.canRetry = false; this.message = '正在生成登录二维码…';
    try {
      const qr = await this.api.createQr();
      if (!this.active || generation !== this.generation) return;
      this.qrUrl = qr.url; this.qrKey = qr.qrcode_key; this.expiresAt = Date.now() + 180000;
      this.message = '使用 B站 App 扫码并确认登录'; this.poll(generation);
    } catch (error) { if (this.active && generation === this.generation) this.message = this.safeError(error as Error); }
    finally { if (this.active && generation === this.generation) this.busy = false; }
  }
  private async verifySavedLogin(): Promise<void> {
    if (!this.active || !this.foreground || this.verifying || this.polling) return;
    const generation = this.generation; this.needsVerification = true; this.verifying = true; this.canRetry = false; this.message = '正在验证 B站账号…';
    try {
      await this.api.verifyLogin();
      if (this.active && generation === this.generation) { this.message = '登录成功'; if (this.foreground) this.onComplete(); }
    } catch (error) { if (this.active && generation === this.generation) { this.message = this.safeError(error as Error); this.canRetry = true; } }
    finally { if (this.active && generation === this.generation) this.verifying = false; }
  }
  private async poll(generation: number): Promise<void> {
    if (!this.active || !this.foreground || generation !== this.generation || this.polling || !this.qrKey) return;
    if (Date.now() >= this.expiresAt) { this.message = '二维码已过期，请刷新'; return; }
    this.polling = true; this.canRetry = false;
    try {
      const code = await this.api.pollQr(this.qrKey, () => this.active && generation === this.generation);
      if (!this.active || generation !== this.generation) return;
      this.failures = 0;
      if (code === 0) { this.message = '登录成功'; if (this.foreground) this.onComplete(); return; }
      if (code === 86038) { this.message = '二维码已过期，请刷新'; return; }
      if (code !== 86090 && code !== 86101) { this.message = `登录状态已变化（${code}），请刷新二维码`; return; }
      this.message = code === 86090 ? '已扫码，请在 B站确认登录' : '使用 B站 App 扫码并确认登录';
      if (this.foreground) this.timer = setTimeout(() => { this.poll(generation); }, 2000);
    } catch (error) {
      if (!this.active || generation !== this.generation) return;
      this.message = this.safeError(error as Error); this.needsVerification = this.api.hasLoginCredentials;
      if (this.needsVerification) this.canRetry = true;
      else if (++this.failures <= 2 && this.foreground) this.timer = setTimeout(() => { this.poll(generation); }, 2000);
      else this.canRetry = true;
    } finally {
      this.polling = false;
      // A refresh can replace the QR while an older HTTP request is finishing.
      if (this.active && this.foreground && generation !== this.generation && this.qrKey) this.poll(this.generation);
    }
  }
  build() {
    Column({ space: 24 }) {
      Text('登录 B站账号').fontSize(24).fontWeight(FontWeight.Bold)
      if (this.qrUrl) { QRCode(this.qrUrl).width(220).height(220).color('#191919').backgroundColor('#FFFFFF') }
      else if (this.busy || this.verifying) { LoadingProgress().width(40).height(40) }
      Text(this.message).fontSize(15).fontColor('#666666').textAlign(TextAlign.Center)
      if (this.needsVerification || this.canRetry) {
        Button(this.verifying ? '正在验证…' : this.needsVerification ? '重试登录验证' : '继续检查登录').fontColor('#FFFFFF').backgroundColor('#D8353F').enabled(!this.verifying)
          .onClick(() => { if (this.needsVerification) this.verifySavedLogin(); else { this.failures = 0; this.poll(this.generation); } })
      }
      Button('刷新二维码').fontColor('#D8353F').backgroundColor('#FFF0F2').enabled(!this.busy && !this.verifying).onClick(() => { this.generate(); })
      if (this.api.demoAvailable) {
        Button('使用演示账号（假数据）').fontColor('#D8353F').backgroundColor('#FFF0F2').onClick(() => {
          this.active = false; ++this.generation; clearTimeout(this.timer); this.api.enableDemo(); this.onComplete();
        })
      }
      Text('手机账号用于浏览、收藏和观看历史。电视使用自己的登录状态；手机登录凭据只保存在本机。').fontSize(13).fontColor('#888888').lineHeight(22)
    }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}

@Component
export struct MyPane {
  @Prop account: Account | undefined = undefined;
  onOpen: (section: string) => void = () => {};
  @Builder
  shortcut(label: string, section: string, icon: Resource) {
    Column({ space: 8 }) {
      SymbolGlyph(icon).fontSize(25).fontColor(['#555555'])
      Text(label).fontSize(12).fontColor('#333333')
    }.layoutWeight(1).padding({ top: 16, bottom: 16 }).onClick(() => { this.onOpen(section); })
  }
  @Builder
  row(label: string, section: string) {
    Row() { Text(label).fontSize(16); Blank(); SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor(['#999999']) }
      .height(52).padding({ left: 16, right: 16 }).width('100%').onClick(() => { this.onOpen(section); })
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 16 }) {
          if (this.account?.face) { Image(this.account.face).width(56).height(56).borderRadius(28) }
          else { SymbolGlyph($r('sys.symbol.person')).fontSize(42).fontColor(['#D8353F']) }
          Column({ space: 6 }) {
            Text(this.account?.uname || '点击登录').fontSize(20).fontWeight(FontWeight.Medium)
            Text(this.account?.demo ? `演示账号 · 硬币 ${this.account.money || 0}` : this.account ? `硬币 ${this.account.money || 0}` : '登录后查看收藏与历史').fontSize(12).fontColor('#888888')
          }.alignItems(HorizontalAlign.Start)
          Blank()
        }.width('100%').padding(20).onClick(() => { this.onOpen(this.account ? 'mySpace' : 'login'); })
        if (this.account?.demo) { Text('演示数据 · 账号资料、收藏、历史和动态均为虚构').fontSize(12).fontColor('#D8353F').lineHeight(18).width('100%').padding({ left: 4, right: 4 }) }
        Row() {
          this.shortcut('我的收藏', 'favorites', $r('sys.symbol.star'))
          this.shortcut('观看记录', 'history', $r('sys.symbol.clock'))
          this.shortcut('我的关注', 'followings', $r('sys.symbol.person'))
          this.shortcut('我的空间', 'mySpace', $r('sys.symbol.house'))
        }.width('100%').backgroundColor('#FFFFFF').borderRadius(16)
        Column() {
          this.row('电视设备', 'connection')
          this.row('关于与隐私', 'about')
          if (this.account?.demo) { this.row('退出演示', 'exitDemo') }
          else if (this.account) { this.row('退出登录', 'logout') }
        }.width('100%').backgroundColor('#FFFFFF').borderRadius(16)
      }.padding({ left: 16, right: 16, bottom: 130 })
    }.align(Alignment.TopStart).height('100%').backgroundColor('#F7F7F7')
  }
}

@Component
export struct FavoriteFoldersPane {
  api: BiliClient = new BiliClient();
  onOpen: (folder: FavoriteFolder) => void = () => {};
  @State folders: FavoriteFolder[] = [];
  @State errorText: string = '';
  @State busy: boolean = false;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    this.busy = true; this.errorText = '';
    try { const folders = await this.api.favoriteFolders(); if (this.active) this.folders = folders; }
    catch (error) { if (this.active) this.errorText = (error as Error).message; }
    finally { if (this.active) this.busy = false; }
  }
  build() {
    List({ space: 8 }) {
      ForEach(this.folders, (folder: FavoriteFolder) => {
        ListItem() {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.star')).fontSize(28).fontColor(['#D8353F'])
            Column({ space: 6 }) { Text(folder.title).fontSize(16); Text(`${folder.media_count} 个视频`).fontSize(12).fontColor('#888888') }.alignItems(HorizontalAlign.Start)
            Blank(); SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
          }.padding(16).width('100%').backgroundColor('#FFFFFF').borderRadius(14).onClick(() => { this.onOpen(folder); })
        }
      }, (folder: FavoriteFolder) => `${folder.id}`)
      ListItem() {
        Column({ space: 12 }) {
          if (this.busy) { LoadingProgress().width(28).height(28) }
          else if (this.errorText) { Text(this.errorText).fontColor('#888888'); Button('重试').onClick(() => { this.load(); }) }
          else if (!this.folders.length) { Text('暂时没有收藏夹').fontColor('#888888') }
        }.width('100%').padding(24)
      }
    }.padding(16).height('100%').backgroundColor('#F7F7F7')
  }
}

@Component
export struct CreatorsPane {
  onLogin?: () => void = undefined;
  mode: string = 'following';
  keyword: string = '';
  api: BiliClient = new BiliClient();
  onOpen: (creator: Creator) => void = () => {};
  private source: PagedItems<Creator> = new PagedItems();
  @State busy: boolean = false;
  @State errorText: string = '';
  private page: number = 0;
  private active: boolean = false;
  private hasMore: boolean = true;
  aboutToAppear(): void { this.active = true; if (!this.page) this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    if (this.busy || !this.hasMore) return;
    this.busy = true; this.errorText = '';
    try {
      const creators = this.mode === 'search' ? await this.api.searchCreators(this.keyword, this.page + 1) : await this.api.followings(this.page + 1);
      if (!this.active) return;
      this.source.append(creators); ++this.page; this.hasMore = creators.length > 0;
    } catch (error) { if (this.active) this.errorText = (error as Error).message; }
    finally { if (this.active) this.busy = false; }
  }
  build() {
    List({ space: 8 }) {
      LazyForEach(this.source, (creator: Creator) => {
        ListItem() {
          Row({ space: 12 }) {
            Image(creator.face).width(44).height(44).borderRadius(22)
            Column({ space: 6 }) {
              Text(creator.uname || creator.name || '').fontSize(16)
              Text(creator.sign || '').fontSize(12).fontColor('#888888').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.padding(12).onClick(() => { this.onOpen(creator); })
        }
      }, (creator: Creator) => `${creator.mid}`)
      ListItem() {
        Column({ space: 10 }) {
          Text(this.errorText).fontColor('#888888')
          if (this.onLogin && this.errorText.includes('验证')) { Button('登录后重试').onClick(() => { this.onLogin?.(); }) }
          if (this.busy) { LoadingProgress().width(28).height(28) }
          else if (this.hasMore) { Button(this.errorText ? '重试' : '加载更多').onClick(() => { this.load(); }) }
        }.width('100%').padding(16)
      }
    }.height('100%').cachedCount(2)
  }
}
