import { BiliClient } from '../services/BiliClient';
import { bundleManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

@Component
export struct AboutPane {
  api: BiliClient = new BiliClient();
  onWithdraw: () => void = () => {};
  onLegal: (document: string) => void = () => {};
  @State versionName: string = '';
  aboutToAppear(): void { bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).then((info: bundleManager.BundleInfo) => { this.versionName = info.versionName; }).catch(() => {}); }
  private openSource(): void {
    (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({ action: 'ohos.want.action.viewData', uri: 'https://github.com/Dcelysia/yueying/tree/harmony-native-v1.0.2' }).catch(() => {});
  }
  @Builder
  row(label: string, action: () => void) {
    Row() { Text(label).fontSize(16); Blank(); SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#999999']) }
      .height(52).width('100%').padding({ left: 16, right: 16 }).onClick(action)
  }
  build() {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 12 }) {
          Image($r('app.media.app_icon')).width(80).height(80).borderRadius(18)
          Text('跃映').fontSize(26).fontWeight(FontWeight.Bold)
          Text(`版本 ${this.versionName} · HarmonyOS 原生版 · dcelysia`).fontSize(13).fontColor('#777777')
          Text('浏览 B站视频，控制同一局域网的电视。手机用于选片和遥控。').fontSize(14).fontColor('#777777').textAlign(TextAlign.Center)
        }.padding(24).width('100%').backgroundColor('#FFFFFF').borderRadius(20)
        Text('项目说明').fontSize(14).fontColor('#777777').width('100%')
        Text('跃映在 PiliPlus 与 NeoBV 开源项目基础上二次开发，保留原作者版权和许可证。本项目与哔哩哔哩官方无关，视频内容版权归原权利人所有。').fontSize(15).lineHeight(24).padding(16).backgroundColor('#FFFFFF').borderRadius(16)
        Column() {
          this.row('开源项目与作者', () => { this.openSource(); })
          this.row('隐私政策', () => { this.onLegal('privacy'); })
          this.row('用户协议', () => { this.onLegal('terms'); })
          this.row('开源项目与作者说明', () => { this.onLegal('notice'); })
          this.row('GPL-3.0 许可证', () => { this.onLegal('license'); })
          this.row('清除搜索历史', () => { this.api.clearSearchHistory(); this.getUIContext().getPromptAction().showToast({ message: '搜索历史已清除' }); })
          this.row('撤回同意并清除本机记录', () => {
            this.getUIContext().showAlertDialog({ title: '撤回同意？', message: '清除本机账号、搜索和电视连接记录，返回首次告知页。电视会继续播放。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '撤回', action: this.onWithdraw } });
          })
        }.width('100%').backgroundColor('#FFFFFF').borderRadius(16)
      }.padding(16)
    }.align(Alignment.TopStart).height('100%').backgroundColor('#F7F7F7')
  }
}
