import { http } from '@kit.NetworkKit';
import url from '@ohos.url';
import { BiliClient, Video, VideoPart } from './BiliClient';
function allowed(uri: url.URL): boolean {
  return ['https:', 'http:'].includes(uri.protocol) && !uri.username && !uri.password && (!uri.port || ['80', '443'].includes(uri.port)) &&
    (uri.hostname === 'b23.tv' || uri.hostname === 'bilibili.com' || uri.hostname.endsWith('.bilibili.com'));
}
export async function sharedVideo(text: string, api: BiliClient): Promise<Video> {
  if (text.length > 16384) throw new Error('分享内容过长');
  const links = text.match(/https?:\/\/[^\s<>"“”]+/g) || [];
  let uri: url.URL | undefined = undefined;
  for (const link of links) {
    try { const candidate = new url.URL(link.replace(/[)\]}>，。！？、；”’]+$/, '')); if (allowed(candidate)) { uri = candidate; break; } } catch (error) {}
  }
  if (!uri && /^(BV1[0-9a-zA-Z]{9}|av[1-9]\d*)$/i.test(text.trim())) uri = new url.URL('https://www.bilibili.com/video/' + text.trim());
  if (!uri) throw new Error('请分享 B站视频链接或 BV/AV 编号');
  const deadline = Date.now() + 10000;
  for (let attempt = 0; uri.hostname === 'b23.tv' && attempt < 5; ++attempt) {
    if (!allowed(uri) || Date.now() >= deadline) throw new Error('短链接解析超时');
    // Follow each allowed redirect ourselves, anonymously, without downloading a body.
    const request = http.createHttp();
    try {
      const response = await request.request(uri.toString(), { method: http.RequestMethod.HEAD, maxRedirects: 0, connectTimeout: Math.min(4000, deadline - Date.now()), readTimeout: Math.min(4000, deadline - Date.now()) });
      const headers = response.header as Record<string, string>;
      const location = headers['location'] || headers['Location'];
      if (response.responseCode < 300 || response.responseCode >= 400 || !location) throw new Error('无法展开短链接，请分享完整视频链接');
      uri = new url.URL(location, uri);
    } finally { request.destroy(); }
  }
  if (!allowed(uri) || uri.hostname === 'b23.tv') throw new Error('短链接没有指向 B站视频');
  let sharedPositionMs: number | undefined = undefined;
  for (const key of ['start_progress', 'dm_progress', 't']) {
    if (!uri.searchParams.has(key)) continue;
    const value = uri.searchParams.get(key);
    if (!value?.trim()) continue;
    const positionMs = Number(value) * (key === 't' ? 1000 : 1);
    // A missing or invalid optional time hint must not block a valid video share.
    if (Number.isFinite(positionMs) && positionMs >= 0 && positionMs <= 2147483647) {
      sharedPositionMs = Math.round(positionMs); break;
    }
  }
  const identity = /^\/video\/(BV1[0-9a-zA-Z]{9}|av[1-9]\d*)/i.exec(uri.pathname);
  if (!identity) {
    const episode = /^\/bangumi\/play\/(ep|ss)([1-9]\d*)/.exec(uri.pathname);
    if (!episode || Number(episode[2]) > 2147483647) throw new Error('暂不支持此分享类型，请使用视频或番剧播放链接');
    return { aid: 0, bvid: '', title: '番剧播放', pic: '', duration: 0, epid: episode[1] === 'ep' ? Number(episode[2]) : undefined, seasonId: episode[1] === 'ss' ? Number(episode[2]) : undefined, historyPositionMs: sharedPositionMs === undefined ? undefined : Math.round(sharedPositionMs) };
  }
  const video = await api.detail(/^av/i.test(identity[1]) ? Number(identity[1].slice(2)) : 0, /^BV/i.test(identity[1]) ? identity[1] : '');
  const pageText = uri.searchParams.get('p');
  const cidText = uri.searchParams.get('cid');
  let sharedPart: VideoPart | undefined = undefined;
  if (uri.searchParams.has('p')) {
    const page = Number(pageText);
    if (!Number.isInteger(page) || page < 1 || page > 10000) throw new Error('分享的分 P 序号无效');
    sharedPart = video.pages?.find((part: VideoPart) => part.page === page);
    if (!sharedPart) throw new Error('分享的分 P 已不存在');
  } else if (uri.searchParams.has('cid')) {
    const cid = Number(cidText);
    if (!Number.isSafeInteger(cid) || cid <= 0) throw new Error('分享的分 P 编号无效');
    sharedPart = video.pages?.find((part: VideoPart) => part.cid === cid);
    if (!sharedPart) throw new Error('分享的分 P 已不存在');
  }
  if (sharedPart) {
    // History time belongs to its own part; an explicit different part starts at zero.
    if (sharedPart.cid !== video.historyCid) video.historyPositionMs = 0;
    video.historyCid = sharedPart.cid;
  }
  if (sharedPositionMs !== undefined) {
    video.historyCid = video.historyCid || video.pages?.[0].cid;
    video.historyPositionMs = Math.round(sharedPositionMs);
  }
  return video;
}
