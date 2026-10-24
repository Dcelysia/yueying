import { http, socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
export interface DiscoveredTelevision { address: string; name: string; deviceId: string; protocol: number }
export function televisionAddress(input: string): string {
  const address = input.trim().replace(/^http:\/\//, '').replace(/\/$/, '');
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d+))?$/.exec(address);
  if (!match) throw new Error('请输入局域网 IPv4 地址和端口');
  const first = Number(match[1]); const second = Number(match[2]); const port = match[5] ? Number(match[5]) : 9838;
  if ([1,2,3,4].some((index: number) => Number(match[index]) > 255) || port < 1 || port > 65535 ||
    !(first === 10 || first === 127 || first === 192 && second === 168 || first === 172 && second >= 16 && second <= 31 || first === 169 && second === 254)) throw new Error('只允许连接局域网电视');
  return `${Number(match[1])}.${Number(match[2])}.${Number(match[3])}.${Number(match[4])}:${port}`;
}
export async function probeTelevision(input: string): Promise<DiscoveredTelevision> {
  const address = televisionAddress(input); const request = http.createHttp();
  try {
    const response = await request.request(`http://${address}/remote/v1/info`, { maxRedirects: 0, connectTimeout: 2000, readTimeout: 2000 });
    if (response.responseCode !== 200) throw new Error('电视服务未就绪');
    const info = JSON.parse(response.result as string) as DiscoveredTelevision;
    if (info.protocol !== 1 || !info.deviceId) throw new Error('此设备不是跃映电视');
    return { address: address, name: info.name || '电视', protocol: 1, deviceId: info.deviceId };
  } finally { request.destroy(); }
}
export class TelevisionDiscovery {
  private generation: number = 0;
  private udp?: socket.UDPSocket;
  private timers: number[] = [];
  private attempted: Set<string> = new Set();
  onDevice: (device: DiscoveredTelevision) => void = () => {};
  onComplete: () => void = () => {};
  async search(knownAddresses: string[]): Promise<void> {
    this.stop(); const generation = this.generation; this.attempted.clear();
    for (const address of knownAddresses) this.probe(address, generation);
    const udp = socket.constructUDPSocketInstance(); this.udp = udp;
    udp.on('message', (message: socket.SocketMessageInfo) => {
      if (generation !== this.generation || message.message.byteLength > 8192) return;
      const body = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(message.message));
      const match = /^location:\s*(http:\/\/[^\s/]+)(?:\/[^\s]*)?/im.exec(body);
      if (match) this.probe(match[1], generation);
    });
    try {
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      if (generation !== this.generation) return;
      const send = (): void => {
        udp.send({ data: 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n', address: { address: '239.255.255.250', port: 1900, family: 1 } }).catch(() => {});
      };
      send(); this.timers.push(setTimeout(send, 1200)); this.timers.push(setTimeout(send, 2800));
    } catch (error) { /* Saved addresses remain usable if multicast is unavailable. */ }
    this.timers.push(setTimeout(() => { if (generation === this.generation) { this.stop(); this.onComplete(); } }, 5500));
  }
  private async probe(input: string, generation: number): Promise<void> {
    let address: string;
    try { address = televisionAddress(input); } catch (error) { return; }
    if (this.attempted.has(address) || this.attempted.size >= 32) return;
    this.attempted.add(address);
    for (let attempt = 0; attempt < 2; ++attempt) {
      try { const device = await probeTelevision(address); if (generation === this.generation) this.onDevice(device); return; }
      catch (error) { if (generation !== this.generation) return; }
    }
  }
  stop(): void {
    ++this.generation; for (const timer of this.timers) clearTimeout(timer); this.timers = [];
    const udp = this.udp; this.udp = undefined; if (udp) udp.close().catch(() => {});
  }
}
