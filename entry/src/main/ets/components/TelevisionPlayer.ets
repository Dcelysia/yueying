import { window } from '@kit.ArkUI';
import { PagedItems } from './PagedItems';
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { TelevisionClient, PlaybackState, QueueItem, CommandPayload } from '../services/TelevisionClient';

@Component
export struct TelevisionPlayer {
  television: TelevisionClient = new TelevisionClient();
  @Prop @Watch('visibilityChanged') visible: boolean = true;
  onClose: () => void = () => {};
  onConnection: () => void = () => {};
  registerBackHandler: (handler: () => boolean) => void = () => {};
  @State snapshot: PlaybackState = this.television.state;
  @State connected: boolean = this.television.connected;
  @State section: string = '选集';
  @State sheetSection: string = '音量';
  @State fullPanel: string = '';
  @State pageWidth: number = 360;
  @State pageHeight: number = 720;
  @State danmakuExpanded: boolean = true;
  @State sponsorExpanded: boolean = true;
  private volumeDragSession: string = '';
  @State canRestoreVolume: boolean = this.television.canRestoreVolume;
  @State showSettings: boolean = false;
  @State fullScreen: boolean = false;
  @State message: string = '';
  @State pendingActions: string[] = [];
  private operations: Map<string, number> = new Map();
  @State pendingSponsorMode: string = '';
  @State pendingSpeed: number = -1;
  private speedAcknowledgedRevision: number = -1;
  private sponsorAcknowledgedRevision: number = -1;
  @State draftPosition: number = -1;
  @State televisionVolume: number = this.television.televisionVolume;
  private dragSession: string = '';
  private commandGeneration: number = 0;
  private mounted: boolean = false;
  private queueSource: PagedItems<QueueItem> = new PagedItems();
  private gesturePosition: number = 0;

  aboutToAppear(): void {
    this.registerBackHandler(() => { if (this.fullPanel) { this.fullPanel = ''; return true; } if (this.fullScreen) { this.toggleFullScreen(); return true; } return false; });
    this.television.onVolumeChanged = (value: number) => { if (this.visible) { this.televisionVolume = value; this.canRestoreVolume = this.television.canRestoreVolume; } };
    this.televisionVolume = this.television.televisionVolume;
    this.television.onActivity = (message: string) => { this.message = message; };
    this.television.onError = (message: string) => { this.message = message; };
    this.mounted = true; this.snapshot = this.television.state; this.connected = this.television.connected;
    this.refreshQueue(); this.attachSnapshot();
  }
  private visibilityChanged(): void {
    if (!this.mounted) return;
    if (this.visible) { this.snapshot = this.television.state; this.connected = this.television.connected; this.televisionVolume = this.television.televisionVolume; this.attachSnapshot(); }
    else this.television.onSnapshot = () => {};
  }
  private attachSnapshot(): void {
    this.television.onSnapshot = (next: PlaybackState) => {
      if (next.playbackId !== this.snapshot.playbackId) {
        ++this.commandGeneration; this.operations.clear(); this.pendingActions = []; this.pendingSponsorMode = ''; this.pendingSpeed = -1; this.speedAcknowledgedRevision = -1; this.sponsorAcknowledgedRevision = -1;
        this.draftPosition = -1; this.message = '';
      }
      this.snapshot = next; this.connected = this.television.connected; this.televisionVolume = this.television.televisionVolume;
      this.refreshQueue();
      if (next.state === 'ERROR') this.message = next.error?.includes('MediaCodec') ? '电视暂时无法解码，请切换画质或重新播放' : next.error ? '电视播放失败：' + next.error : '电视播放失败，请重新播放';
      if (this.pendingSponsorMode && (next.sponsorSkipMode === this.pendingSponsorMode || this.sponsorAcknowledgedRevision >= 0 && next.revision > this.sponsorAcknowledgedRevision)) { this.pendingSponsorMode = ''; this.sponsorAcknowledgedRevision = -1; }
      if (this.pendingSpeed > 0 && (Math.abs(next.speed - this.pendingSpeed) < 0.01 || this.speedAcknowledgedRevision >= 0 && next.revision > this.speedAcknowledgedRevision)) { this.pendingSpeed = -1; this.speedAcknowledgedRevision = -1; }
    };
  }
  aboutToDisappear(): void {
    this.registerBackHandler(() => false);
    this.mounted = false; ++this.commandGeneration;
    this.television.onSnapshot = () => {};
    this.television.onVolumeChanged = () => {};
    this.television.onActivity = () => {};
    this.television.onError = () => {};
    if (this.fullScreen) this.restoreWindow();
  }
  private async restoreWindow(): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext);
      await mainWindow.setPreferredOrientation(window.Orientation.UNSPECIFIED);
      await mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (error) { /* Window can disappear while the page is being removed. */ }
  }
  private async toggleFullScreen(): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const next = !this.fullScreen;
      await mainWindow.setPreferredOrientation(next ? window.Orientation.LANDSCAPE : window.Orientation.UNSPECIFIED);
      await mainWindow.setWindowSystemBarEnable(next ? [] : ['status', 'navigation']);
      this.fullPanel = ''; this.showSettings = false; this.fullScreen = next;
    } catch (error) { this.message = '无法切换全屏，请重试'; }
  }
  private isPending(action: string): boolean { return this.pendingActions.includes(action); }
  private async perform(action: string, payload: CommandPayload = {}): Promise<void> {
    if (this.isPending(action) || !this.canControl()) return;
    const operation = ++this.commandGeneration;
    const playbackId = this.snapshot.playbackId;
    // Each action has its own pending state; a slow setting does not lock other controls.
    this.operations.set(action, operation); this.pendingActions = Array.from(this.operations.keys()); this.message = '';
    try {
      await this.television.command(action, payload);
      if (this.mounted && this.operations.get(action) === operation && playbackId === this.snapshot.playbackId) {
        this.message = '';
        if (action === 'speed' && this.pendingSpeed > 0) this.speedAcknowledgedRevision = this.snapshot.revision;
        if (action === 'sponsorSkipMode' && this.pendingSponsorMode) this.sponsorAcknowledgedRevision = this.snapshot.revision;
      }
    } catch (error) {
      if (this.mounted && this.operations.get(action) === operation) {
        this.message = (error as Error).message;
        if (action === 'sponsorSkipMode') this.pendingSponsorMode = '';
        if (action === 'speed') this.pendingSpeed = -1;
      }
    } finally {
      if (this.mounted && this.operations.get(action) === operation) {
        this.operations.delete(action); this.pendingActions = Array.from(this.operations.keys());
        if (action === 'seek') this.draftPosition = -1;
      }
    }
  }
  private chooseSponsorMode(mode: string): void {
    if (!this.connected || this.snapshot.sponsorSkipMode === undefined || this.isPending('sponsorSkipMode') || mode === this.snapshot.sponsorSkipMode) return;
    this.sponsorAcknowledgedRevision = -1; this.pendingSponsorMode = mode;
    this.perform('sponsorSkipMode', { mode: mode });
  }
  private playbackSpeed(): number { return this.pendingSpeed > 0 ? this.pendingSpeed : this.snapshot.speed; }
  private chooseSpeed(speed: number): void {
    if (!this.canControl() || this.isPending('speed') || Math.abs(speed - this.playbackSpeed()) < 0.01) return;
    this.speedAcknowledgedRevision = -1; this.pendingSpeed = speed; this.perform('speed', { value: speed });
  }
  private openSettings(section: string): void {
    if (this.fullScreen) this.fullPanel = section;
    else { this.sheetSection = '音量'; this.showSettings = true; }
  }
  private hasAdjacent(step: number): boolean {
    const index = this.snapshot.queue?.findIndex((item: QueueItem) => item.aid === this.snapshot.aid && item.cid === this.snapshot.cid) ?? -1;
    return index >= 0 && index + step >= 0 && index + step < this.snapshot.queue.length;
  }
  private refreshQueue(): void {
    const queue = this.snapshot.queue || [];
    let changed = queue.length !== this.queueSource.totalCount();
    for (let index = 0; !changed && index < queue.length; ++index) {
      const previous = this.queueSource.getData(index); const current = queue[index];
      changed = previous.aid !== current.aid || previous.cid !== current.cid || previous.title !== current.title;
    }
    if (changed) this.queueSource.replace(queue);
  }
  private time(milliseconds: number): string {
    const seconds = Math.floor(Math.max(0, milliseconds) / 1000);
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }
  private canControl(): boolean { return this.connected && !!this.snapshot.playbackId && this.snapshot.aid > 0 && this.snapshot.state !== 'TRANSITIONING'; }
  private textColor(dark: boolean): string { return dark ? '#F3F3F5' : '#242424'; }
  private secondaryColor(dark: boolean): string { return dark ? '#B7B7C0' : '#777777'; }
  private activeSection(modal: boolean, expanded: boolean): string { return expanded ? this.fullPanel : modal ? this.sheetSection : this.section; }
  private sectionLabel(section: string): string {
    if (section === '倍速') return `${Number.isInteger(this.playbackSpeed()) ? this.playbackSpeed().toFixed(1) : this.playbackSpeed()}× 倍速`;
    if (section === '画质') return this.snapshot.qualities?.[`${this.snapshot.qualityId}`] || '画质';
    if (section === '弹幕') return this.snapshot.danmakuEnabled ? '弹幕 · 开' : '弹幕 · 关';
    if (section === '音量') return `音量 ${Math.round(this.televisionVolume)}%`;
    return section;
  }
  private sectionIcon(section: string): Resource {
    switch (section) {
      case '选集': return $r('sys.symbol.list_bullet');
      case '倍速': return $r('sys.symbol.video_speed');
      case '画质': return $r('sys.symbol.hd_plus_rectangle');
      case '弹幕': return $r('sys.symbol.AI_subtitles');
      case '音量': return $r('sys.symbol.speaker_wave_2');
      case '广告跳过': return $r('sys.symbol.fast_forward');
      default: return $r('sys.symbol.slider_horizontal_2');
    }
  }
  private playbackLabel(): string {
    if (!this.connected) return '连接已断开';
    if (this.snapshot.aid <= 0) return '等待选择视频';
    switch (this.snapshot.state) {
      case 'PLAYING': return '正在电视播放';
      case 'PAUSED': return '电视已暂停';
      case 'TRANSITIONING': return '电视正在加载…';
      case 'ERROR': return '电视播放失败';
      default: return '已连接电视';
    }
  }
  private hasSponsorPrompt(): boolean {
    const segment = this.snapshot.sponsorSegment;
    return this.canControl() && !!segment && this.snapshot.positionMs >= segment.startMs && this.snapshot.positionMs < segment.endMs;
  }
  private seekOffset(offset: number): void {
    this.perform('seek', { positionMs: Math.max(0, Math.min(this.snapshot.durationMs, this.snapshot.positionMs + offset)) });
  }
  private selectEpisode(item: QueueItem): void {
    if (item.aid <= 0 || item.cid <= 0 || item.aid === this.snapshot.aid && item.cid === this.snapshot.cid) return;
    this.perform('episode', { aid: item.aid, cid: item.cid });
  }
  private changeVolume(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin) this.volumeDragSession = this.snapshot.playbackId;
    if (mode !== SliderChangeMode.Click && this.volumeDragSession !== this.snapshot.playbackId) return;
    this.television.setVolume(value, mode !== SliderChangeMode.Click && mode !== SliderChangeMode.End);
    if (mode === SliderChangeMode.Click || mode === SliderChangeMode.End) this.volumeDragSession = '';
  }
  private changeProgress(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin) this.dragSession = this.snapshot.playbackId;
    this.draftPosition = value;
    if (mode === SliderChangeMode.Click || mode === SliderChangeMode.End) {
      if (mode === SliderChangeMode.Click || this.dragSession === this.snapshot.playbackId) this.perform('seek', { positionMs: Math.round(value) });
      else this.draftPosition = -1;
    }
  }
  @Builder
  iconButton(icon: Resource, label: string, action: () => void, enabled: boolean, dark: boolean, size: number = 48, filled: boolean = false) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon).fontSize(size >= 60 ? 36 : 23).fontColor([enabled ? (filled ? '#D8353F' : this.textColor(dark)) : this.secondaryColor(dark)])
    }.width(size).height(size).backgroundColor(filled ? (dark ? '#38303B' : '#FFF0F2') : Color.Transparent)
      .accessibilityText(label).enabled(enabled).onClick(action)
  }
  @Builder
  choice(label: string, selected: () => boolean, action: () => void, enabled: () => boolean, dark: boolean) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 5 }) {
        if (selected()) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor(['#D8353F']) }
        Text(label).fontSize(14).fontColor(selected() ? '#D8353F' : this.textColor(dark))
      }.padding({ left: 12, right: 12 })
    }.height(36).borderRadius(18).backgroundColor(selected() ? (dark ? '#3B252C' : '#FFF0F2') : Color.Transparent)
      .border({ width: 1, color: selected() ? '#DCA3A7' : dark ? '#48484E' : '#DDDDDF' })
      .enabled(enabled()).accessibilityText(label).accessibilitySelected(selected()).onClick(action)
  }
  @Builder
  sectionTabs(dark: boolean, fullScreen: boolean = false, modal: boolean = false) {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(['选集', '倍速', '画质', '弹幕', '音量', '广告跳过'], (label: string) => {
          Button({ type: ButtonType.Capsule }) {
            Row({ space: 6 }) {
              SymbolGlyph(this.sectionIcon(label)).fontSize(18).fontColor([!fullScreen && this.activeSection(modal, false) === label ? '#D8353F' : this.secondaryColor(dark)])
              Text(this.sectionLabel(label)).fontSize(14).fontColor(!fullScreen && this.activeSection(modal, false) === label ? '#D8353F' : this.secondaryColor(dark))
            }.padding({ left: 12, right: 12 })
          }.height(48).backgroundColor(!fullScreen && this.activeSection(modal, false) === label ? (dark ? '#3B252C' : '#FFF0F2') : Color.Transparent)
            .onClick(() => { if (fullScreen) this.openSettings(label); else if (modal) this.sheetSection = label; else this.section = label; })
        }, (label: string) => label)
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').align(Alignment.Start)
  }
  @Builder
  episodes(expanded: boolean, dark: boolean) {
    if (!this.snapshot.queue?.length) {
      Text(this.snapshot.state === 'TRANSITIONING' ? '选集信息正在同步' : '当前视频没有其他选集').fontSize(14).fontColor(this.secondaryColor(dark)).width('100%').padding({ top: 20, bottom: 20 })
    } else if (!this.snapshot.queue.some((item: QueueItem) => item.aid === this.snapshot.aid)) {
      Text('选集信息正在同步').fontSize(14).fontColor(this.secondaryColor(dark)).width('100%').padding({ top: 20, bottom: 20 })
    } else {
      List({ space: 8 }) {
        LazyForEach(this.queueSource, (item: QueueItem, index: number) => {
          ListItem() {
            if (expanded) {
              Row({ space: 12 }) {
                Text(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '▥' : `${index + 1}`.padStart(2, '0')).fontSize(14).fontColor(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '#D8353F' : this.secondaryColor(dark))
                Text(item.title).fontSize(15).fontColor(this.textColor(dark)).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              }.padding(12).height(72).width('100%').borderRadius(12)
                .backgroundColor(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? (dark ? '#3B252C' : '#FFF0F2') : Color.Transparent)
                .border({ width: 1, color: item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '#DCA3A7' : Color.Transparent })
                .enabled(this.canControl()).onClick(() => { this.selectEpisode(item); })
            } else {
              Column() {
                Column() {
                  Text(item.title).fontSize(14).fontColor(this.textColor(dark)).fontWeight(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? FontWeight.Medium : FontWeight.Normal).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Blank()
                  Text(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? (this.snapshot.state === 'PLAYING' ? '播放中' : '当前选集') : `第 ${index + 1} 集`)
                    .fontSize(11).fontColor(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '#D8353F' : this.secondaryColor(dark)).width('100%')
                }.height(104).width('100%').padding(12).borderRadius(12)
                  .backgroundColor(item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '#FFF5F5' : '#F5F5F7')
                  .border({ width: 1, color: item.aid === this.snapshot.aid && item.cid === this.snapshot.cid ? '#DCA3A7' : '#E0E0E3' })
                  .enabled(this.canControl()).onClick(() => { this.selectEpisode(item); })
              }.height('100%').justifyContent(FlexAlign.Center).width(this.snapshot.queue.length === 1 ? 220 : 180)
            }
          }
        }, (item: QueueItem) => `${item.aid}:${item.cid}`)
      }.height(expanded ? Math.max(140, this.pageHeight - 100) : 140).width('100%').listDirection(expanded ? Axis.Vertical : Axis.Horizontal).scrollBar(BarState.Off).cachedCount(2)
    }
  }
  @Builder
  volumeControl(dark: boolean, expanded: boolean) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.smartscreen')).fontSize(24).fontColor(['#D8353F'])
        Column({ space: 4 }) {
          Text('电视音量').fontSize(16).fontColor(this.textColor(dark))
          Text(this.snapshot.volumeMode === 'player' ? '播放器音量 · 手机音量不变' : '手机音量保持不变').fontSize(12).fontColor(this.secondaryColor(dark))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.canControl() && this.snapshot.volumeMode !== 'unavailable' ? `${Math.round(this.televisionVolume)}%` : '—').fontSize(28).fontWeight(FontWeight.Medium).fontColor('#D8353F')
      }.width('100%')
      Row({ space: 6 }) {
        this.iconButton($r('sys.symbol.minus'), '电视音量减', () => { this.television.adjustVolume(-1); }, this.canControl() && this.televisionVolume > 0 && this.snapshot.volumeMode !== 'unavailable', dark, 40, true)
        Slider({ value: this.televisionVolume, min: 0, max: 100, step: 1 })
          .selectedColor('#D8353F').layoutWeight(1).enabled(this.canControl() && this.snapshot.volumeMode !== 'unavailable')
          .onChange((value: number, mode: SliderChangeMode) => { this.changeVolume(value, mode); })
        this.iconButton($r('sys.symbol.plus'), '电视音量加', () => { this.television.adjustVolume(1); }, this.canControl() && this.televisionVolume < 100 && this.snapshot.volumeMode !== 'unavailable', dark, 40, true)
      }.height(44).width('100%')
      Row() {
        Text(!this.connected ? '电视未连接' : !this.canControl() ? '等待电视开始播放' : this.televisionVolume !== this.snapshot.volume ? '正在同步到电视…' : this.snapshot.volumeMode === 'system' ? '按电视音量档位调节' : '微调每次 1%').fontSize(12).fontColor(this.secondaryColor(dark)).layoutWeight(1)
        Button(this.televisionVolume > 0 ? '静音' : this.canRestoreVolume ? '恢复' : '已静音').fontSize(14).fontColor('#D8353F').backgroundColor(Color.Transparent)
          .enabled(this.canControl() && this.snapshot.volumeMode !== 'unavailable' && (this.televisionVolume > 0 || this.canRestoreVolume)).onClick(() => {
            this.television.toggleMute();
          })
      }.height(36).width('100%')
    }.width('100%').padding(expanded ? 0 : 16).borderRadius(24).backgroundColor(expanded ? Color.Transparent : dark ? '#24252D' : '#F6F6F8')
  }
  @Builder
  danmakuControl(dark: boolean) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        SymbolGlyph(this.sectionIcon('弹幕')).fontSize(23).fontColor([this.secondaryColor(dark)])
        Text('电视弹幕').fontSize(16).fontColor(this.textColor(dark)).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.snapshot.danmakuEnabled }).selectedColor('#D8353F').enabled(this.canControl() && !this.isPending('danmaku'))
          .onChange((enabled: boolean) => { if (enabled !== this.snapshot.danmakuEnabled) this.perform('danmaku', { enabled: enabled }); })
      }.height(56).width('100%')
      if (this.snapshot.danmakuSettings) {
        Row() {
          Text('弹幕样式').fontSize(16).fontColor(this.textColor(dark)).layoutWeight(1)
          SymbolGlyph(this.danmakuExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down')).fontSize(16).fontColor([this.secondaryColor(dark)])
        }.height(48).width('100%').onClick(() => { this.danmakuExpanded = !this.danmakuExpanded; })
        if (this.danmakuExpanded) {
          this.styleSlider('字号', this.snapshot.danmakuSettings.scale, 0.5, 4, 0.1, 'scale', dark)
          Text('显示区域').fontSize(13).fontColor(this.textColor(dark)).width('100%').margin({ top: 12, bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
            ForEach([0.25, 0.5, 0.75, 1], (area: number) => {
              this.choice(area === 0.25 ? '1/4 屏' : area === 0.5 ? '半屏' : area === 0.75 ? '3/4 屏' : '全屏', () => Math.abs(this.snapshot.danmakuSettings!.area - area) < 0.01,
                () => { this.perform('danmakuSettings', { area: area }); }, () => this.canControl() && this.snapshot.danmakuEnabled && !this.isPending('danmakuSettings'), dark)
            }, (area: number) => `${area}`)
          }.width('100%').margin({ bottom: 16 })
          this.styleSlider('不透明度', this.snapshot.danmakuSettings.opacity, 0.1, 1, 0.1, 'opacity', dark)
          this.styleSlider('密度', this.snapshot.danmakuSettings.density, 0.2, 1, 0.2, 'density', dark)
          Text('弹幕类型').fontSize(13).fontColor(this.textColor(dark)).width('100%').margin({ top: 12, bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
            ForEach(['rolling', 'top', 'bottom'], (type: string) => {
              this.choice(type === 'rolling' ? '滚动' : type === 'top' ? '顶部固定' : '底部固定', () => this.snapshot.danmakuSettings!.types.includes(type), () => {
                const types = this.snapshot.danmakuSettings!.types.slice(); const index = types.indexOf(type);
                if (index >= 0) types.splice(index, 1); else types.push(type);
                this.perform('danmakuSettings', { types: types });
              }, () => this.canControl() && this.snapshot.danmakuEnabled && !this.isPending('danmakuSettings'), dark)
            }, (type: string) => type)
          }.width('100%').margin({ bottom: 12 })
        }
      }
    }.width('100%')
  }
  @Builder
  styleSlider(label: string, value: number, minimum: number, maximum: number, step: number, field: string, dark: boolean) {
    Column({ space: 0 }) {
      Row() { Text(label).fontSize(13).fontColor(this.textColor(dark)); Blank(); Text(`${value.toFixed(1)}`).fontSize(12).fontColor(this.secondaryColor(dark)) }.width('100%')
      Slider({ value: value, min: minimum, max: maximum, step: step }).selectedColor('#D8353F').width('100%')
        .enabled(this.canControl() && this.snapshot.danmakuEnabled && !this.isPending('danmakuSettings'))
        .onChange((next: number, mode: SliderChangeMode) => {
          if (mode !== SliderChangeMode.Click && mode !== SliderChangeMode.End) return;
          if (field === 'scale') this.perform('danmakuSettings', { scale: next });
          else if (field === 'opacity') this.perform('danmakuSettings', { opacity: next });
          else this.perform('danmakuSettings', { density: next });
        })
    }.width('100%')
  }
  @Builder
  sponsorControl(dark: boolean) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        SymbolGlyph(this.sectionIcon('广告跳过')).fontSize(23).fontColor([this.secondaryColor(dark)])
        Text('电视赞助片段').fontSize(16).fontColor(this.textColor(dark)).layoutWeight(1)
        if (this.isPending('sponsorSkipMode')) { LoadingProgress().width(16).height(16).color('#D8353F') }
        else { SymbolGlyph(this.sponsorExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down')).fontSize(16).fontColor([this.secondaryColor(dark)]) }
      }.height(56).width('100%').onClick(() => { this.sponsorExpanded = !this.sponsorExpanded; })
      if (this.sponsorExpanded) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
          ForEach(['prompt', 'auto', 'off'], (mode: string) => {
            this.choice(mode === 'prompt' ? '提示跳过' : mode === 'auto' ? '自动跳过' : '关闭', () => (this.pendingSponsorMode || this.snapshot.sponsorSkipMode) === mode,
              () => { this.chooseSponsorMode(mode); }, () => this.canControl() && this.snapshot.sponsorSkipMode !== undefined && !this.isPending('sponsorSkipMode'), dark)
          }, (mode: string) => mode)
        }.width('100%')
        Text(this.snapshot.sponsorSkipMode === undefined ? '当前电视版本暂不支持此设置。' : '由电视跳过社区标注片段，手机锁屏或退出后仍可自动跳过。')
          .fontSize(12).fontColor(this.secondaryColor(dark)).lineHeight(19).width('100%').margin({ top: 8, bottom: 12 })
      }
    }.width('100%')
  }
  @Builder
  sectionContent(dark: boolean, expanded: boolean, modal: boolean = false) {
    Column({ space: 0 }) {
      if (this.activeSection(modal, expanded) === '选集') { this.episodes(expanded, dark) }
      else if (this.activeSection(modal, expanded) === '倍速') {
        Row() {
          Text('播放速度').fontSize(13).fontColor(this.textColor(dark)).layoutWeight(1)
          if (this.isPending('speed')) { LoadingProgress().width(16).height(16).color('#D8353F') }
        }.width('100%').margin({ top: 12, bottom: 8 })
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
          ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], (speed: number) => {
            this.choice(`${speed}x`, () => Math.abs(this.playbackSpeed() - speed) < 0.01, () => { this.chooseSpeed(speed); }, () => this.canControl() && !this.isPending('speed'), dark)
          }, (speed: number) => `${speed}`)
        }.width('100%')
      } else if (this.activeSection(modal, expanded) === '画质') {
        if (!this.snapshot.qualities || Object.keys(this.snapshot.qualities).length === 0) { Text('电视开始播放后可选择画质').fontSize(14).fontColor(this.secondaryColor(dark)).width('100%') }
        else {
          Text('电视画质').fontSize(13).fontColor(this.textColor(dark)).width('100%').margin({ top: 12, bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
            ForEach(Object.keys(this.snapshot.qualities), (key: string) => {
              this.choice(this.snapshot.qualities![key], () => this.snapshot.qualityId === Number(key), () => { this.perform('quality', { value: Number(key) }); }, () => this.canControl() && !this.isPending('quality'), dark)
            }, (key: string) => key)
          }.width('100%')
        }
      } else if (this.activeSection(modal, expanded) === '音量') { this.volumeControl(dark, expanded) }
      else if (this.activeSection(modal, expanded) === '弹幕') { this.danmakuControl(dark) }
      else if (this.activeSection(modal, expanded) === '广告跳过') { this.sponsorControl(dark) }
      else if (this.activeSection(modal, expanded) === '更多') {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          this.choice('电视返回 / 停止播放', () => false, () => { this.perform('back'); }, () => this.canControl(), dark)
          Button('断开遥控，电视继续播').fontSize(14).fontColor('#D8353F').backgroundColor(Color.Transparent)
            .onClick(() => { this.television.disconnect(); this.onClose(); })
          Button('重新连接 / 换电视').fontSize(14).fontColor('#D8353F').backgroundColor(Color.Transparent).onClick(() => { this.fullPanel = ''; this.showSettings = false; if (this.fullScreen) this.toggleFullScreen(); this.onConnection(); })
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  compactControls(dark: boolean) {
    Row() {
      this.iconButton($r('sys.symbol.backward_end_fill'), '上一集', () => { this.perform('previous'); }, this.canControl() && this.hasAdjacent(-1), dark)
      this.iconButton($r('sys.symbol.gobackward_10'), '后退 10 秒', () => { this.seekOffset(-10000); }, this.canControl() && this.snapshot.durationMs > 0, dark)
      this.iconButton($r('sys.symbol.goforward_10'), '前进 10 秒', () => { this.seekOffset(10000); }, this.canControl() && this.snapshot.durationMs > 0, dark)
      Blank()
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) { SymbolGlyph($r('sys.symbol.stop_circle')).fontSize(20).fontColor(['#D8353F']); Text('停止电视播放').fontSize(14).fontColor('#D8353F') }
      }.height(48).backgroundColor(Color.Transparent).enabled(this.canControl()).onClick(() => { this.perform('stop'); })
    }.width('100%').margin({ top: 16 })
  }
  @Builder
  controlsPanel(dark: boolean, expanded: boolean, modal: boolean = false) {
    Column({ space: 0 }) {
      if (this.message) { Text(this.message).fontSize(13).fontColor(this.snapshot.state === 'ERROR' ? '#D8353F' : this.secondaryColor(dark)).width('100%').margin({ bottom: 12 }) }
      if (!expanded) { this.sectionTabs(dark, false, modal) }
      Column() { this.sectionContent(dark, expanded, modal) }.width('100%').margin({ top: 12 })
      if (!expanded) { this.compactControls(dark) }
    }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  settingsContent() {
    Column({ space: 0 }) {
      Row() {
        Text('电视遥控').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        this.iconButton($r('sys.symbol.xmark'), '关闭遥控设置', () => { this.showSettings = false; }, true, false)
      }.padding({ left: 16, right: 4 }).width('100%')
      Scroll() { this.controlsPanel(false, false, true) }.align(Alignment.TopStart).constraintSize({ maxHeight: this.pageHeight * 0.8 - 72 }).width('100%')
    }.width('100%').backgroundColor('#FFFFFF')
  }
  @Builder
  sponsorPrompt() {
    Column({ space: 4 }) {
      Text(this.hasSponsorPrompt() ? `${this.snapshot.sponsorSegment!.category === 'sponsor' ? '赞助片段' : '可跳过片段'} · 剩余 ${Math.max(0, Math.ceil((this.snapshot.sponsorSegment!.endMs - this.snapshot.positionMs) / 1000))} 秒` : this.snapshot.sponsorSkipNotice || '')
        .fontSize(14).fontColor('#EEEEF2').width('100%')
      if (this.hasSponsorPrompt()) {
        Row() {
          Button('跳过片段').fontSize(14).fontColor('#EF8B94').backgroundColor(Color.Transparent).enabled(!this.isPending('skipSponsor'))
            .onClick(() => { if (this.hasSponsorPrompt()) this.perform('skipSponsor', { segmentId: this.snapshot.sponsorSegment!.id }); })
          Blank()
          Button('本次不跳').fontSize(14).fontColor('#EF8B94').backgroundColor(Color.Transparent)
            .onClick(() => { if (this.hasSponsorPrompt()) this.perform('dismissSponsor', { segmentId: this.snapshot.sponsorSegment!.id }); })
        }.height(36).width('100%')
      }
    }.padding({ left: 16, right: 16, top: 8, bottom: 8 }).borderRadius(24).backgroundColor('#292A32').width('100%')
  }
  @Builder
  placeholder() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Keep the background gesture surface separate from buttons and the slider.
      Column().width('100%').height(Math.max(0, this.placeholderHeight() - (this.fullScreen ? 200 : 124))).margin({ top: this.fullScreen ? 56 : 44 })
        .gesture(GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Horizontal }).onActionStart(() => {
            if (this.canControl() && this.snapshot.durationMs > 0) { this.dragSession = this.snapshot.playbackId; this.gesturePosition = this.snapshot.positionMs; this.draftPosition = this.gesturePosition; }
          }).onActionUpdate((event: GestureEvent) => {
            if (this.canControl() && this.snapshot.durationMs > 0 && this.draftPosition >= 0 && this.dragSession === this.snapshot.playbackId) this.draftPosition = Math.max(0, Math.min(this.snapshot.durationMs, this.gesturePosition + event.offsetX * 125));
          }).onActionEnd(() => {
            if (this.draftPosition >= 0 && this.dragSession === this.snapshot.playbackId) this.perform('seek', { positionMs: Math.round(this.draftPosition) });
            else this.draftPosition = -1;
          }).onActionCancel(() => { this.draftPosition = -1; }),
          TapGesture({ count: 2 }).onAction(() => { this.perform(this.snapshot.state === 'PLAYING' ? 'pause' : 'play'); })
        ))
      Row({ space: 0 }) {
        this.iconButton($r('sys.symbol.chevron_left'), this.fullScreen ? '退出全屏' : '返回', () => { if (this.fullScreen) this.toggleFullScreen(); else this.onClose(); }, true, true)
        SymbolGlyph($r('sys.symbol.cast_smartscreen')).fontSize(18).fontColor(['#FFFFFF']).margin({ right: 8 })
        Text(this.fullScreen && this.snapshot.title ? `${this.snapshot.title} · ${this.television.name}` : this.television.name || '电视播放').fontSize(13).lineHeight(20).fontColor('#FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) { SymbolGlyph($r('sys.symbol.slider_horizontal_2')).fontSize(18).fontColor(['#FFFFFF']); Text(this.fullScreen ? '更多' : '遥控').fontSize(14).fontColor('#FFFFFF') }
        }.height(48).padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent).onClick(() => { this.openSettings('更多'); })
      }.width('100%').height(48).padding({ right: 4 })
      if (this.hasSponsorPrompt() || this.snapshot.sponsorSkipNotice) {
        Scroll() { this.sponsorPrompt() }.align(Alignment.TopStart).width('100%').height(Math.max(0, this.placeholderHeight() - (this.fullScreen ? 200 : 124))).padding({ left: 16, right: 16 }).margin({ top: this.fullScreen ? 56 : 44 })
      } else {
        Column({ space: 4 }) {
          if (this.draftPosition < 0 && this.placeholderHeight() >= 200) {
            Row({ space: 24 }) {
              if (this.fullScreen) { this.iconButton($r('sys.symbol.backward_end_fill'), '上一集', () => { this.perform('previous'); }, this.canControl() && this.hasAdjacent(-1), true) }
              this.iconButton(this.snapshot.state === 'PLAYING' ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'), this.snapshot.state === 'PLAYING' ? '暂停电视' : '继续播放', () => { this.perform(this.snapshot.state === 'PLAYING' ? 'pause' : 'play'); }, this.canControl(), true, this.fullScreen ? 64 : 48, true)
              if (this.fullScreen) { this.iconButton($r('sys.symbol.forward_end_fill'), '下一集', () => { this.perform('next'); }, this.canControl() && this.hasAdjacent(1), true) }
            }.justifyContent(FlexAlign.Center)
          }
          Text(this.draftPosition < 0 ? this.playbackLabel() : `${Math.round((this.draftPosition - this.gesturePosition) / 1000)} 秒 · 松手跳转`).fontSize(12).lineHeight(17).fontColor('#C5C5CE').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).hitTestBehavior(HitTestMode.None)
          if (this.placeholderHeight() >= 240) { Text('左右滑动微调进度 · 双击播放 / 暂停').fontSize(12).fontColor('#A8A8B4').hitTestBehavior(HitTestMode.None) }
        }.width('100%').height(Math.max(0, this.placeholderHeight() - (this.fullScreen ? 200 : 124))).margin({ top: this.fullScreen ? 56 : 44 }).justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.Transparent)
      }
      Column({ space: 0 }) {
        Row() {
          Text(this.time(this.draftPosition >= 0 ? this.draftPosition : this.snapshot.positionMs) + ' / ' + this.time(this.snapshot.durationMs)).fontSize(12).lineHeight(17).fontColor('#FFFFFF').layoutWeight(1)
          if (this.placeholderHeight() < 200) { this.iconButton(this.snapshot.state === 'PLAYING' ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'), this.snapshot.state === 'PLAYING' ? '暂停电视' : '继续播放', () => { this.perform(this.snapshot.state === 'PLAYING' ? 'pause' : 'play'); }, this.canControl(), true, 40) }
          if (!this.fullScreen || this.placeholderHeight() < 200) { this.iconButton($r('sys.symbol.forward_end_fill'), '下一集', () => { this.perform('next'); }, this.canControl() && this.hasAdjacent(1), true, 40) }
          this.iconButton(this.fullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') : $r('sys.symbol.arrow_up_left_and_arrow_down_right'), this.fullScreen ? '退出全屏' : '全屏遥控', () => { this.toggleFullScreen(); }, true, true, 40)
        }.width('100%').height(40)
        Slider({ value: this.draftPosition >= 0 ? this.draftPosition : this.snapshot.positionMs, min: 0, max: Math.max(1, this.snapshot.durationMs) })
          .selectedColor('#EF6B75').trackColor('#62626D').trackThickness(3).blockSize({ width: 10, height: 10 }).blockColor('#EF6B75').width('100%').height(40)
          .enabled(this.canControl() && this.snapshot.durationMs > 0 && !this.isPending('seek')).onChange((value: number, mode: SliderChangeMode) => { this.changeProgress(value, mode); })
        if (this.fullScreen) { this.sectionTabs(true, true) }
      }.width('100%').padding({ left: 12, right: 12 }).align(Alignment.Bottom).position({ x: 0, y: this.placeholderHeight() - (this.fullScreen ? 128 : 80) })
      if (this.fullScreen && this.fullPanel) {
        Column().width('100%').height('100%').backgroundColor('#55000000').onClick(() => { this.fullPanel = ''; })
        Column({ space: 0 }) {
          Row({ space: 8 }) {
            SymbolGlyph(this.sectionIcon(this.fullPanel)).fontSize(20).fontColor(['#EEEEF2'])
            Text(this.fullPanel).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#EEEEF2').layoutWeight(1)
            this.iconButton($r('sys.symbol.xmark'), '关闭面板', () => { this.fullPanel = ''; }, true, true)
          }.width('100%').padding({ left: 20, right: 4 })
          Divider().color('#393A43')
          Scroll() { this.controlsPanel(true, true) }.align(Alignment.TopStart).width('100%').layoutWeight(1)
        }.width(Math.min(360, this.pageWidth * 0.55)).height('100%').backgroundColor('#191A20').borderRadius({ topLeft: 20, bottomLeft: 20 })
          .align(Alignment.TopStart).position({ x: this.pageWidth - Math.min(360, this.pageWidth * 0.55), y: 0 }).clip(true)
      }
    }.width('100%').height(this.placeholderHeight()).backgroundColor('#15161C')
  }
  private placeholderHeight(): number { return this.fullScreen ? this.pageHeight : Math.min(this.pageWidth * 9 / 16, this.pageHeight); }
  build() {
    Column({ space: 0 }) {
      this.placeholder()
      if (!this.fullScreen) {
        Scroll() {
          Column({ space: 0 }) {
            Column({ space: 8 }) {
              Text(this.snapshot.title || '选择视频后在电视上观看').fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).fontColor('#242424').width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.connected ? '视频由电视播放，手机用于选集和遥控。' : '电视会继续播放，恢复连接后自动同步当前进度。').fontSize(12).lineHeight(16).fontColor('#777777').width('100%')
            }.padding({ left: 16, right: 16, top: 16, bottom: 12 }).width('100%').alignItems(HorizontalAlign.Start)
            Divider().color('#EEEEF0')
            this.controlsPanel(false, false)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.align(Alignment.TopStart).layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
      .onAreaChange((_previous: Area, current: Area) => {
        const width = Number(current.width); const height = Number(current.height);
        if (width !== this.pageWidth) this.pageWidth = width;
        if (height !== this.pageHeight) this.pageHeight = height;
      })
      .bindSheet($$this.showSettings, this.settingsContent(), { height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true, onDisappear: () => { this.showSettings = false; } })
  }
}
