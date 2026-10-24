import { util } from '@kit.ArkTS';

@Component
export struct LegalDocumentPane {
  document: string = 'privacy';
  @State paragraphs: string[] = [];
  @State errorText: string = '';
  private active: boolean = false;
  async aboutToAppear(): Promise<void> {
    this.active = true;
    const file = this.document === 'terms' ? 'user-agreement.md' : this.document === 'notice' ? 'NOTICE.md' : this.document === 'license' ? 'GPL-3.0.txt' : 'privacy-policy.md';
    try {
      const bytes = await this.getUIContext().getHostContext()!.resourceManager.getRawFileContent(file);
      const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes);
      if (this.active) this.paragraphs = text.split('\n\n').filter((paragraph: string) => paragraph.trim().length > 0);
    } catch (error) { if (this.active) this.errorText = '暂时无法读取内置文件，请重新打开'; }
  }
  aboutToDisappear(): void { this.active = false; }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.errorText) { Text(this.errorText).fontColor('#D8353F') }
        ForEach(this.paragraphs, (paragraph: string) => {
          Text(paragraph.replace(/^#{1,3} /, '')).fontSize(paragraph.startsWith('# ') ? 23 : paragraph.startsWith('## ') ? 18 : 15)
            .fontWeight(paragraph.startsWith('#') ? FontWeight.Medium : FontWeight.Normal).lineHeight(paragraph.startsWith('#') ? 29 : 24)
            .fontColor('#333333').width('100%').copyOption(CopyOptions.InApp)
        }, (_paragraph: string, index: number) => `${index}`)
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
    }.align(Alignment.TopStart).width('100%').height('100%').backgroundColor('#F7F7F7')
  }
}
