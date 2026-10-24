import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { Action, inputConsumer, KeyCode, KeyEvent } from '@kit.InputKit';

interface SharedVideo { id: string; text: string }
export default class EntryAbility extends UIAbility {
  private foreground: boolean = false;
  private connected: boolean = false;
  private windowReady: boolean = false;
  private subscribedUp: boolean = false;
  private subscribedDown: boolean = false;
  private heldDirection: number = 0;
  private holdDelay: number = -1;
  private holdRepeat: number = -1;
  private shareSequence: number = 0;
  private pendingShare?: SharedVideo;
  private session: string = Date.now().toString();
  private readonly up = (event: KeyEvent): void => { this.volumeKey(event, 1); };
  private readonly down = (event: KeyEvent): void => { this.volumeKey(event, -1); };
  private readonly connectionChanged = (connected: boolean): void => { this.connected = connected; this.updateKeys(); };
  private readonly pullShare = (): void => { if (this.pendingShare) this.context.eventHub.emit('shared-video', this.pendingShare); };
  private readonly acknowledgeShare = (id: string): void => { if (this.pendingShare?.id === id) this.pendingShare = undefined; };
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.eventHub.on('remote-connected', this.connectionChanged);
    this.context.eventHub.on('pull-share', this.pullShare);
    this.context.eventHub.on('acknowledge-share', this.acknowledgeShare);
    this.receiveShare(want);
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void { this.receiveShare(want); }
  private async receiveShare(want: Want): Promise<void> {
    if (want.action !== 'ohos.want.action.sendData') return;
    const sequence = ++this.shareSequence; this.pendingShare = undefined;
    try {
      const data = await systemShare.getSharedData(want);
      if (sequence !== this.shareSequence) return;
      let text = '';
      for (const record of data.getRecords()) {
        if (['general.text', 'general.plain-text', 'general.hyperlink'].includes(record.utd) && record.content) text = `${text}\n${record.content}`.trim().slice(0, 16384);
      }
      if (!text) return;
      this.pendingShare = { id: `${this.session}-${sequence}`, text: text };
      this.context.eventHub.emit('shared-video', this.pendingShare);
    } catch (error) { /* Untrusted share payloads never log content or trigger navigation here. */ }
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    const mainWindow = stage.getMainWindowSync(); this.windowReady = true;
    mainWindow.setWindowLayoutFullScreen(false);
    mainWindow.setWindowSystemBarProperties({ statusBarColor: '#F7F7F7', statusBarContentColor: '#191919', navigationBarColor: '#FFFFFF', navigationBarContentColor: '#191919' });
    stage.loadContent('pages/Index'); this.updateKeys();
  }
  onForeground(): void { this.foreground = true; this.updateKeys(); this.context.eventHub.emit('foreground', true); }
  onBackground(): void { this.foreground = false; this.updateKeys(); this.context.eventHub.emit('foreground', false); }
  onWindowStageDestroy(): void { this.windowReady = false; this.updateKeys(); }
  onDestroy(): void {
    ++this.shareSequence; this.pendingShare = undefined; this.connected = false; this.updateKeys();
    this.context.eventHub.off('remote-connected', this.connectionChanged);
    this.context.eventHub.off('pull-share', this.pullShare); this.context.eventHub.off('acknowledge-share', this.acknowledgeShare);
  }
  private stopHold(): void {
    clearTimeout(this.holdDelay); clearInterval(this.holdRepeat); this.holdDelay = -1; this.holdRepeat = -1; this.heldDirection = 0;
  }
  private volumeKey(event: KeyEvent, direction: number): void {
    if (event.action === Action.UP || event.action === Action.CANCEL) { if (this.heldDirection === direction || event.action === Action.CANCEL) this.stopHold(); return; }
    if (event.action !== Action.DOWN || !this.connected || !this.foreground || !this.windowReady || this.heldDirection === direction) return;
    this.stopHold(); this.heldDirection = direction; this.context.eventHub.emit('television-volume-key', direction);
    this.holdDelay = setTimeout(() => {
      this.context.eventHub.emit('television-volume-key', direction);
      this.holdRepeat = setInterval(() => { this.context.eventHub.emit('television-volume-key', direction); }, 120);
    }, 350);
  }
  private updateKeys(): void {
    if (this.connected && this.foreground && this.windowReady) {
      try {
        if (!this.subscribedUp) { inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_UP, action: 2, isRepeat: true }, this.up); this.subscribedUp = true; }
        if (!this.subscribedDown) { inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_DOWN, action: 2, isRepeat: true }, this.down); this.subscribedDown = true; }
        return;
      } catch (error) { this.context.eventHub.emit('volume-key-error', '无法接管音量键，可用播放器内滑块调节电视音量'); }
    }
    this.stopHold();
    if (this.subscribedUp) { try { inputConsumer.off('keyPressed', this.up); this.subscribedUp = false; } catch (error) {} }
    if (this.subscribedDown) { try { inputConsumer.off('keyPressed', this.down); this.subscribedDown = false; } catch (error) {} }
  }
}
