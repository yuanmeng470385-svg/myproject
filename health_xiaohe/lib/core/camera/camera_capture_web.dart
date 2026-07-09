// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Web 平台摄像头采集 — getUserMedia + Canvas 抽帧
// 每1秒抓取一帧 JPEG，分辨率 640x480，质量 0.7
import 'dart:async';
import 'dart:js' as js;
import 'camera_capture_base.dart';

class CameraCapture extends CameraCaptureBase {
  Timer? _timer;
  bool _capturing = false;
  int _frameCount = 0;

  @override
  Future<bool> hasPermission() async {
    try {
      final c = Completer<bool>();
      js.context['__camPermCb'] = js.allowInterop((bool ok) {
        c.complete(ok);
      });
      js.context.callMethod('eval', ['''
(async function() {
  try {
    var s = await navigator.mediaDevices.getUserMedia({video: true});
    s.getTracks().forEach(function(t) { t.stop(); });
    window.__camPermCb(true);
  } catch(e) {
    window.__camPermCb(false);
  }
})()
''']);
      return c.future;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() => hasPermission();

  @override
  Future<void> startCapture(void Function(String base64Jpeg) onFrame) async {
    _capturing = true;
    _frameCount = 0;

    js.context['__camOnFrame'] = js.allowInterop((String b64) {
      if (!_capturing || b64.isEmpty) return;
      _frameCount++;
      if (_frameCount <= 3) print('[Camera] Frame #$_frameCount len=${b64.length}');
      onFrame(b64);
    });

    js.context.callMethod('eval', ['''
(async function() {
  try {
    // 请求摄像头
    var stream = await navigator.mediaDevices.getUserMedia({
      video: {width: 640, height: 480, frameRate: 15}
    });
    console.log('[Camera] stream acquired');

    // 创建全屏视频背景 — 覆盖整个页面，镜面翻转
    var video = document.createElement('video');
    video.autoplay = true;
    video.playsInline = true;
    video.muted = true;
    video.srcObject = stream;
    video.id = '__camPreview';
    Object.assign(video.style, {
      position: 'fixed',
      top: '0',
      left: '0',
      width: '100vw',
      height: '100vh',
      objectFit: 'cover',
      zIndex: '0',
      transform: 'scaleX(-1)'
    });
    // 插入到 Flutter canvas 之前，作为背景
    var flutterView = document.querySelector('flt-glass-pane')?.parentElement;
    if (flutterView && flutterView.parentElement) {
      flutterView.parentElement.insertBefore(video, flutterView);
    } else {
      document.body.insertBefore(video, document.body.firstChild);
    }
    await video.play();

    // 创建 canvas 用于抽帧
    var canvas = document.createElement('canvas');
    canvas.width = 640;
    canvas.height = 480;
    var ctx = canvas.getContext('2d');

    // 每1秒抽一帧
    window.__camInterval = setInterval(function() {
      if (video.readyState >= 2) {
        ctx.drawImage(video, 0, 0, 640, 480);
        var b64 = canvas.toDataURL('image/jpeg', 0.7).split(',')[1];
        window.__camOnFrame(b64);
      }
    }, 1000);

    window.__camVideo = video;
    window.__camStream = stream;
    window.__camCanvas = canvas;
    console.log('[Camera] capture started at 1fps');
  } catch(e) { console.error('[Camera] setup error:', ''+e); }
})()
''']);
  }

  @override
  Future<void> stopCapture() async {
    _capturing = false;
    _timer?.cancel();
    _timer = null;
    js.context.callMethod('eval', ['''
clearInterval(window.__camInterval);
try { var s = window.__camStream; if(s) s.getTracks().forEach(function(t){t.stop()}); } catch(e) {}
try { var v = window.__camVideo; if(v) { v.pause(); v.srcObject=null; v.remove(); } } catch(e) {}
try { var p = document.getElementById('__camPreview'); if(p) p.remove(); } catch(e) {}
delete window.__camVideo;
delete window.__camStream;
delete window.__camCanvas;
delete window.__camInterval;
delete window.__camOnFrame;
''']);
  }

  @override
  void dispose() {
    stopCapture();
  }
}
