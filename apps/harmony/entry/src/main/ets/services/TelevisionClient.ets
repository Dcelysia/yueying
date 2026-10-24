// Protocol-compatible with packages/bili_remote_core; GPL-3.0.
import { webSocket } from '@kit.NetworkKit';
import { probeTelevision, televisionAddress, DiscoveredTelevision } from './TelevisionDiscovery';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
export interface QueueItem { aid: number; cid: number; title: string; bvid?: string }
export interface DanmakuSettings { scale: number; area: number; opacity: number; density: number; types: string[] }
export interface SponsorSegment { id: string; category: string; startMs: number; endMs: number }
export interface PlaybackState {
  error?: string; type?: string; revision: number; playbackId: string; state: string; title: string;
  aid: number; cid: number; positionMs: number; durationMs: number; volume: number;
  volumeMode?: string; danmakuSettings?: DanmakuSettings; sponsorSegment?: SponsorSegment;
  sponsorSkipMode?: string; sponsorSkipNotice?: string;
  speed: number; danmakuEnabled: boolean; qualities?: Record<string, string>; qualityId?: number; queue: QueueItem[];
}
export interface CommandPayload { direction?: number; density?: number; types?: string[]; page?: number; epid?: number; seasonId?: number; mode?: string; segmentId?: string; scale?: number; area?: number; opacity?: number; enabled?: boolean; value?: number | boolean; positionMs?: number; aid?: number; bvid?: string; cid?: number; title?: string; queue?: QueueItem[] }
interface ReceiverInfo { protocol: number; deviceId: string; name: string }
interface ReceiverMessage extends PlaybackState {
  protocol?: number; deviceId?: string; name?: string; message?: string; requestId?: string; token?: string;
}
interface PendingCommand { accept: () => void; reject: (error: Error) => void; timer: number }
export class TelevisionClient {
  socket?: webSocket.WebSocket;
  connected: boolean = false;
  name: string = '';
  private generation: number = 0;
  private store?: preferences.Preferences;
  private token: string = '';
  private savedDeviceId: string = '';
  address: string = '';
  private shouldReconnect: boolean = false;
  private foreground: boolean = true;
  private retryTimer: number = -1;
  private retryAttempt: number = 0;
  private connectionAttempt?: Promise<void>;
  private connectingAddress: string = '';
  get hasSavedTelevision(): boolean { return !!this.savedDeviceId && !!this.address; }
  get reconnectEnabled(): boolean { return this.shouldReconnect; }
  private volumeTarget?: number;
  private volumeQueued?: number;
  private volumeStepQueued?: number;
  private sendingVolume: boolean = false;
  private volumeDispatchTimer: number = -1;
  private volumeFeedbackTimer: number = -1;
  private volumeAcknowledgedRevision?: number;
  private volumeRestoreTarget?: number;
  private volumeBeforeMute?: number;
  get canRestoreVolume(): boolean { return this.volumeBeforeMute !== undefined; }
  private volumeFromDrag: boolean = false;
  private lastVolumeSentAt: number = 0;
  get televisionVolume(): number { return this.volumeTarget === undefined ? this.state.volume : this.volumeTarget; }
  onVolumeChanged: (value: number) => void = () => {};
  private hardwareFeedbackUntil: number = 0;
  onHardwareVolume: (value: number) => void = () => {};
  onHardwareAvailability: (enabled: boolean) => void = () => {};
  private hardwareAvailable: boolean = false;
  private updateHardwareAvailability(): void {
    const enabled = this.connected && this.foreground && !!this.state.playbackId && this.state.aid > 0 && this.state.state !== 'TRANSITIONING' && this.state.volumeMode !== 'unavailable';
    if (enabled !== this.hardwareAvailable) { this.hardwareAvailable = enabled; this.onHardwareAvailability(enabled); }
  }
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'remote_session' });
    this.clientId = await this.store.get('clientId', this.clientId) as string;
    this.address = await this.store.get('address', '') as string;
    this.token = await this.store.get('token', '') as string;
    this.savedDeviceId = await this.store.get('deviceId', '') as string;
    this.name = await this.store.get('name', '我的电视') as string;
    await this.store.put('clientId', this.clientId); await this.store.flush();
    this.shouldReconnect = await this.store.get('selected', false) as boolean;
    this.onChange();
    if (this.shouldReconnect && this.address) this.connect(this.address, true).catch(() => {});
  }
  setForeground(foreground: boolean): void {
    this.foreground = foreground; this.updateHardwareAvailability(); if (foreground) this.onSnapshot(this.state);
    clearTimeout(this.retryTimer); this.retryTimer = -1;
    if (!foreground) { this.hardwareFeedbackUntil = 0; this.resetVolumeControls(); }
    else if (!this.connected && this.shouldReconnect && this.address) this.connect(this.address, true).catch(() => {});
  }
  private scheduleReconnect(): void {
    if (!this.shouldReconnect || !this.foreground || !this.address || this.retryTimer !== -1) return;
    const delay = Math.min(10000, 750 * Math.pow(2, Math.min(4, this.retryAttempt++)));
    this.retryTimer = setTimeout(() => { this.retryTimer = -1; this.connect(this.address, true).catch(() => {}); }, delay);
  }
  private canAdjustVolume(): boolean {
    return this.connected && this.foreground && !!this.state.playbackId && this.state.aid > 0 && this.state.state !== 'TRANSITIONING' && this.state.volumeMode !== 'unavailable';
  }
  adjustVolume(direction: number): void {
    if ((direction !== -1 && direction !== 1) || !this.canAdjustVolume()) return;
    this.hardwareFeedbackUntil = Date.now() + 1400;
    if (this.state.volumeMode === 'system') {
      // The receiver knows its real system-volume steps; percentages are quantized.
      this.volumeQueued = undefined; this.volumeFromDrag = false; this.clearVolumeFeedback();
      this.volumeStepQueued = direction; this.dispatchQueuedVolume();
    } else this.setVolume(this.televisionVolume + direction);
    this.onHardwareVolume(this.televisionVolume);
  }
  setVolume(value: number, dragging: boolean = false): void {
    if (!this.canAdjustVolume()) return;
    this.volumeStepQueued = undefined; this.volumeRestoreTarget = undefined;
    const target = Math.max(0, Math.min(100, Math.round(value)));
    if (target === this.volumeTarget) {
      if (!dragging) { this.volumeFromDrag = false; this.dispatchQueuedVolume(); }
      return;
    }
    clearTimeout(this.volumeFeedbackTimer); this.volumeAcknowledgedRevision = undefined;
    this.volumeTarget = target; this.volumeQueued = target; this.volumeFromDrag = dragging;
    this.onVolumeChanged(target);
    if (Date.now() < this.hardwareFeedbackUntil) this.onHardwareVolume(target);
    this.dispatchQueuedVolume();
  }
  toggleMute(): void {
    if (!this.canAdjustVolume()) return;
    if (this.televisionVolume > 0) {
      this.volumeBeforeMute = this.televisionVolume; this.setVolume(0);
    } else if (this.volumeBeforeMute !== undefined) this.restoreVolume(this.volumeBeforeMute);
  }
  private restoreVolume(value: number): void {
    if (!this.canAdjustVolume()) return;
    this.setVolume(value); this.volumeRestoreTarget = Math.max(0, Math.min(100, Math.round(value)));
  }
  private dispatchQueuedVolume(): void {
    clearTimeout(this.volumeDispatchTimer); this.volumeDispatchTimer = -1;
    if (this.sendingVolume || (this.volumeQueued === undefined && this.volumeStepQueued === undefined) || !this.canAdjustVolume()) return;
    const delay = this.volumeFromDrag ? Math.max(0, 80 - (Date.now() - this.lastVolumeSentAt)) : 0;
    if (delay > 0) this.volumeDispatchTimer = setTimeout(() => { this.volumeDispatchTimer = -1; this.flushVolume(); }, delay);
    else this.flushVolume();
  }
  private async flushVolume(): Promise<void> {
    if (this.sendingVolume || (this.volumeQueued === undefined && this.volumeStepQueued === undefined) || !this.canAdjustVolume()) return;
    const value = this.volumeQueued; const direction = this.volumeStepQueued; this.volumeQueued = undefined; this.volumeStepQueued = undefined; this.sendingVolume = true; this.lastVolumeSentAt = Date.now();
    const generation = this.generation; const playbackId = this.state.playbackId;
    try {
      if (direction !== undefined) await this.command('adjustVolume', { direction: direction });
      else await this.command('volume', { value: value });
      if (direction === undefined && generation === this.generation && playbackId === this.state.playbackId && this.foreground && this.volumeQueued === undefined && this.volumeStepQueued === undefined) {
        this.volumeAcknowledgedRevision = this.state.revision;
        // Keep the target while snapshots catch up, matching the Flutter controller.
        this.volumeFeedbackTimer = setTimeout(() => { this.clearVolumeFeedback(); }, 2000);
      }
    } catch (error) {
      if (generation === this.generation && playbackId === this.state.playbackId) {
        this.volumeQueued = undefined; this.volumeStepQueued = undefined; this.clearVolumeFeedback(); this.onError((error as Error).message);
      }
    } finally {
      this.sendingVolume = false; this.dispatchQueuedVolume();
    }
  }
  private clearVolumeFeedback(): void {
    clearTimeout(this.volumeFeedbackTimer); this.volumeFeedbackTimer = -1;
    this.volumeAcknowledgedRevision = undefined; this.volumeTarget = undefined; this.volumeRestoreTarget = undefined;
    this.onVolumeChanged(this.state.volume);
    if (Date.now() < this.hardwareFeedbackUntil) this.onHardwareVolume(this.state.volume);
  }
  private resetVolumeControls(): void {
    clearTimeout(this.volumeDispatchTimer); this.volumeDispatchTimer = -1; this.volumeQueued = undefined; this.volumeStepQueued = undefined;
    this.clearVolumeFeedback();
  }
  private pending: Map<string, PendingCommand> = new Map();
  private commandNumber: number = 0;
  private clientId: string = `native-${Date.now()}`;
  state: PlaybackState = { revision: -1, playbackId: '', state: 'STOPPED', title: '', aid: 0, cid: 0, positionMs: 0, durationMs: 0, volume: 0, speed: 1, danmakuEnabled: true, queue: [] };
  onChange: () => void = () => {};
  onActivity: (message: string) => void = () => {};
  // High-frequency playback updates belong to the mounted player, not the app shell.
  onSnapshot: (state: PlaybackState) => void = () => {};
  onError: (message: string) => void = () => {};
  connect(input: string, automatic: boolean = false): Promise<void> {
    const address = televisionAddress(input);
    // Foreground resume and a manual tap can request the same connection together.
    if (this.connectionAttempt && this.connectingAddress === address) return this.connectionAttempt;
    this.connectingAddress = address;
    const attempt = this.openConnection(address, automatic);
    this.connectionAttempt = attempt;
    const clearAttempt = (): void => { if (this.connectionAttempt === attempt) this.connectionAttempt = undefined; };
    attempt.then(clearAttempt, clearAttempt);
    return attempt;
  }
  private async openConnection(input: string, automatic: boolean): Promise<void> {
    const address = televisionAddress(input);
    if (!automatic) { this.address = address; this.shouldReconnect = true; this.retryAttempt = 0; }
    clearTimeout(this.retryTimer); this.retryTimer = -1;
    this.closeTransport(); const generation = this.generation;
    let info: DiscoveredTelevision;
    try { info = await probeTelevision(address); }
    catch (error) { if (generation === this.generation) this.scheduleReconnect(); throw error as Error; }
    if (generation !== this.generation) throw new Error('连接已取消');
    if (automatic && this.savedDeviceId && info.deviceId !== this.savedDeviceId) { this.shouldReconnect = false; throw new Error('电视地址已变化，请重新搜索'); }
    if (this.savedDeviceId && info.deviceId !== this.savedDeviceId) this.volumeBeforeMute = undefined;
    const host = address;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    this.state.revision = -1;
    await new Promise<void>((accept, reject) => {
      const timer = setTimeout(() => { if (generation === this.generation) this.connectionLost(generation); reject(new Error('电视握手超时')); }, 5000);
      socket.on('open', () => { socket.send(JSON.stringify({ type: 'hello', protocol: 1, clientId: this.clientId, token: this.savedDeviceId === info.deviceId ? this.token : '' })).catch(() => {}); });
      socket.on('message', (_error: BusinessError, value: string | ArrayBuffer) => {
        if (generation !== this.generation || typeof value !== 'string' || value.length > 1048576) return;
        try {
          const data = JSON.parse(value) as ReceiverMessage;
          if (data.type === 'welcome') {
            if (data.protocol !== 1 || data.deviceId !== info.deviceId) throw new Error('电视身份不匹配');
            clearTimeout(timer); this.connected = true; this.name = data.name || info.name; this.address = address; this.savedDeviceId = info.deviceId; this.token = data.token || '';
            this.retryAttempt = 0; this.store?.put('name', this.name); this.store?.put('address', address); this.store?.put('deviceId', info.deviceId); this.store?.put('token', this.token); this.store?.put('selected', true); this.store?.flush();
            this.onChange(); accept();
          } else if (data.type === 'state' && data.revision > this.state.revision) {
            const playbackChanged = data.playbackId !== this.state.playbackId;
            const volumeChanged = data.volume !== this.state.volume;
            this.state = data;
            if (playbackChanged) this.resetVolumeControls();
            else if (this.volumeAcknowledgedRevision !== undefined && data.revision > this.volumeAcknowledgedRevision && (data.volume === this.volumeTarget || data.volumeMode === 'system') && !this.sendingVolume && this.volumeQueued === undefined && this.volumeStepQueued === undefined) {
              const restoreTarget = this.volumeRestoreTarget;
              this.clearVolumeFeedback();
              // Restoring a rounded percentage can land one system step below the saved level.
              if (restoreTarget !== undefined && data.volumeMode === 'system' && data.volume < restoreTarget) {
                this.volumeStepQueued = 1; this.dispatchQueuedVolume();
              }
            }
            if (volumeChanged) {
              this.onVolumeChanged(this.televisionVolume);
              if (Date.now() < this.hardwareFeedbackUntil) this.onHardwareVolume(this.televisionVolume);
            }
            this.updateHardwareAvailability(); if (this.foreground) this.onSnapshot(data);
          }
          else if (data.type === 'ack' || data.type === 'error') {
            const pending = this.pending.get(data.requestId || '');
            if (pending) { clearTimeout(pending.timer); this.pending.delete(data.requestId!); data.type === 'ack' ? pending.accept() : pending.reject(new Error(data.message || '电视执行失败')); }
            if (data.type === 'error') { this.onError(data.message || '电视执行失败'); if (!this.connected) { clearTimeout(timer); reject(new Error(data.message || '连接失败')); } }
          }
        } catch (error) { clearTimeout(timer); this.connectionLost(generation); reject(error as Error); }
      });
      socket.on('close', () => { if (generation === this.generation) { clearTimeout(timer); this.connectionLost(generation); reject(new Error('电视连接已断开')); } });
      socket.on('error', () => { if (generation === this.generation) { clearTimeout(timer); this.connectionLost(generation); reject(new Error('无法连接电视')); } });
      socket.connect(`ws://${host}/remote/v1`).catch(() => { clearTimeout(timer); this.connectionLost(generation); reject(new Error('无法连接电视')); });
    });
  }
  async command(action: string, payload: CommandPayload = {}): Promise<void> {
    if (!this.connected || !this.socket) throw new Error('电视未连接');
    const requestId = `${Date.now()}-${++this.commandNumber}`;
    const socket = this.socket;
    await new Promise<void>((accept, reject) => {
      const timer = setTimeout(() => { this.pending.delete(requestId); reject(new Error('电视响应超时')); }, 10000);
      this.pending.set(requestId, { accept: accept, reject: reject, timer: timer });
      socket.send(JSON.stringify({ type: 'command', requestId: requestId, action: action, playbackId: this.state.playbackId, payload: payload })).catch(() => {
        clearTimeout(timer); this.pending.delete(requestId); reject(new Error('命令发送失败'));
      });
    });
  }
  disconnect(): void {
    this.shouldReconnect = false; clearTimeout(this.retryTimer); this.retryTimer = -1; this.store?.put('selected', false); this.store?.flush(); this.closeTransport();
  }
  dispose(): void { this.shouldReconnect = false; clearTimeout(this.retryTimer); this.retryTimer = -1; this.closeTransport(); }
  async clearSaved(): Promise<void> { this.disconnect(); this.address = ''; this.token = ''; this.savedDeviceId = ''; await this.store?.clear(); await this.store?.flush(); }
  private connectionLost(generation: number): void { if (generation !== this.generation) return; this.closeTransport(); this.scheduleReconnect(); }
  private closeTransport(): void {
    ++this.generation; this.connected = false; this.resetVolumeControls();
    this.pending.forEach((pending: PendingCommand) => { clearTimeout(pending.timer); pending.reject(new Error('连接已断开')); }); this.pending.clear();
    const socket = this.socket; this.socket = undefined; if (socket) socket.close().catch(() => {});
    this.updateHardwareAvailability(); this.onChange(); this.onSnapshot(this.state);
  }
}
