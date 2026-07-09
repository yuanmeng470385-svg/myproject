// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import { router, promptAction } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { VoiceClient } from '../common/net/VoiceClient';
import { AudioEngine } from '../common/audio/AudioEngine';
import { CameraEngine } from '../common/camera/CameraEngine';
import { Space, FS } from '../common/theme/Tokens';

interface CallParams {
  conversationId?: string;
}

/// 语音通话页（对应 Flutter call_page）。
/// WebSocket 连后端 voice/ws + AudioEngine 采集 16k PCM 上行、播放 24k PCM 下行。
/// 后端 server VAD 自动断句并响应（无需手动 commit）。视频帧上行见后续 CameraEngine。
@Entry
@Component
struct Call {
  @State status: string = '正在连接…';
  @State transcript: string = '';
  @State connected: boolean = false;
  @State muted: boolean = false;
  @State videoOn: boolean = false;
  private client: VoiceClient = new VoiceClient();
  private engine: AudioEngine = new AudioEngine();
  private cameraEngine: CameraEngine = new CameraEngine();
  private xController: XComponentController = new XComponentController();
  private pingTimer: number = -1;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as CallParams;
    const convId: string = (params !== null && params !== undefined && params.conversationId !== undefined)
      ? params.conversationId : '';

    this.client.onConnected = (cid: string) => {
      this.connected = true;
      this.status = '已连接 · 请说话';
      this.requestPermsAndStartAudio();
    };
    this.client.onText = (t: string) => {
      // AI 流式 delta；完整转录走 onAiText，避免重复，这里不追加
    };
    this.client.onUserText = (t: string) => {
      if (t.length > 0) {
        this.transcript += '你：' + t + '\n\n';
      }
    };
    this.client.onAiText = (t: string) => {
      if (t.length > 0) {
        this.transcript += '小云：' + t + '\n\n';
      }
    };
    this.client.onAudio = (b64: string) => {
      this.engine.enqueue(b64);
    };
    this.client.onDone = () => {
      this.status = '已连接 · 请继续';
    };
    this.client.onError = (m: string) => {
      this.status = '错误：' + m;
    };
    this.client.onClose = () => {
      this.connected = false;
      this.status = '连接已关闭';
    };
    this.client.connect(convId);
    this.pingTimer = setInterval(() => {
      this.client.ping();
    }, 15000);
  }

  // 申请麦克风权限后再启动音频（权限弹窗需要页面已渲染、context 就绪）
  private async requestPermsAndStartAudio(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      await atManager.requestPermissionsFromUser(ctx, perms);
    } catch (e) {
      // 权限被拒或失败，仍尝试启动音频（让 AudioEngine 自报错）
    }
    await this.startAudio();
  }

  private async startAudio(): Promise<void> {
    try {
      await this.engine.startPlayback();
      this.engine.onPcm = (b64: string) => {
        this.client.sendAudio(b64);
      };
      await this.engine.startCapture();
    } catch (e) {
      this.status = '音频启动失败（需麦克风权限/真机）';
    }
  }

  private async startVideo(surfaceId: string): Promise<void> {
    try {
      const ctx: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const atManager2: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const camPerms: Permissions[] = ['ohos.permission.CAMERA'];
      await atManager2.requestPermissionsFromUser(ctx, camPerms);
      this.cameraEngine.onFrame = (b64: string) => {
        this.client.sendImage(b64);
      };
      await this.cameraEngine.start(ctx, surfaceId);
    } catch (e) {
      promptAction.showToast({ message: '摄像头启动失败' });
      this.videoOn = false;
    }
  }

  private async toggleVideo(): Promise<void> {
    if (this.videoOn) {
      this.videoOn = false;
      await this.cameraEngine.stop();
    } else {
      this.videoOn = true; // XComponent onLoad 时触发 startVideo
    }
  }

  async aboutToDisappear(): Promise<void> {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
    await this.engine.stop();
    await this.cameraEngine.stop();
    this.client.close();
  }

  @Builder
  controlButton(icon: Resource, bg: string, onTap: () => void) {
    Column() {
      SymbolGlyph(icon).fontSize(28).fontColor(['#FFFFFF'])
    }
    .width(64).height(64).borderRadius(32)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
  }

  build() {
    Column() {
      Blank().height(60)

      if (this.videoOn) {
        XComponent({ id: 'camPreview', type: XComponentType.SURFACE, controller: this.xController })
          .onLoad(() => {
            const sid: string = this.xController.getXComponentSurfaceId();
            this.startVideo(sid);
          })
          .width(220).height(300).borderRadius(16)
      } else {
        Column() {
          Text('🌿').fontSize(64)
        }
        .width(140).height(140).borderRadius(70)
        .backgroundColor(this.connected ? '#337FB3A8' : '#22FFFFFF')
        .justifyContent(FlexAlign.Center)
      }

      Text('健康小云')
        .fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF').margin({ top: Space.lg })

      Text(this.status)
        .fontSize(FS.body).fontColor('#B0C4D4')
        .margin({ top: Space.sm })

      Scroll() {
        Text(this.transcript.length > 0 ? this.transcript : '（语音对话将显示在这里）')
          .fontSize(FS.body).fontColor('#D8E4EC')
          .width('100%').textAlign(TextAlign.Start).lineHeight(22)
      }
      .layoutWeight(1).width('100%').padding(Space.lg)
      .align(Alignment.Top)

      Row() {
        this.controlButton(this.muted ? $r('sys.symbol.mic_slash') : $r('sys.symbol.mic'), '#33FFFFFF', () => {
          this.muted = !this.muted;
          this.engine.muted = this.muted;
          promptAction.showToast({ message: this.muted ? '已静音' : '已取消静音' });
        })
        this.controlButton($r('sys.symbol.camera'), this.videoOn ? '#7FB3A8' : '#33FFFFFF', () => {
          this.toggleVideo();
        })
        this.controlButton($r('sys.symbol.phone_down_fill'), '#D9695F', () => {
          router.back();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ bottom: 60 })
    }
    .width('100%').height('100%')
    .backgroundColor('#1A2A3A')
  }
}
