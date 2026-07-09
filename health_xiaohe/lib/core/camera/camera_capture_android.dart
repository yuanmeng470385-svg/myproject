// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Android 平台摄像头采集 — camera 包 + image stream
//
// 帧采集用 startImageStream（YUV420 流），而非 takePicture：
// takePicture 会暂停实时预览（对焦+快门），导致 CameraPreview 周期性黑屏“看不到自己”。
// image stream 与 CameraPreview 共存、预览不中断；回调里节流到 3 秒一帧，
// 把 YUV420 → JPEG 的转码丢到 isolate（compute），不阻塞 UI。
import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'camera_capture_base.dart';

class CameraCapture extends CameraCaptureBase {
  CameraController? _controller;
  bool _capturing = false;
  bool _converting = false; // 一帧转码进行中，期间丢弃后续帧
  bool _isFront = false;
  int _frameSeq = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // 1 帧/秒：后端只缓存最新一帧、由下一个 audio 包捎带给 DashScope，且用户说完
  // 一句话(commit)就丢弃 pending 帧。间隔太长(如 3s)会让短句 turn 完全踩不到采集点，
  // 导致 DashScope 整轮收不到图像、AI“看不到你”。1s 能覆盖正常说话窗口。
  static const _frameIntervalMs = 1000;

  @override
  Future<bool> hasPermission() async {
    try {
      final cameras = await availableCameras();
      return cameras.isNotEmpty;
    } catch (e) {
      debugPrint('[Camera] availableCameras failed: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final cameras = await availableCameras();
      return cameras.isNotEmpty;
    } catch (e) {
      debugPrint('[Camera] requestPermission failed: $e');
      return false;
    }
  }

  CameraController? get controller => _controller;

  @override
  Widget? buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    final preview = c.value.previewSize;
    if (preview == null) return null;

    // 预览内容；前置摄像头水平镜像（像照镜子）。镜像只作用于预览，
    // 发送给 AI 的帧用原始 YUV，方向保持真实。
    Widget child = CameraPreview(c);
    if (_isFront) {
      child = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: child,
      );
    }

    // previewSize 是传感器横向尺寸（如 640x480）；竖屏显示需宽高互换，
    // 再用 FittedBox.cover 填满并裁边 —— 比手算 aspectRatio 缩放可靠。
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: child,
        ),
      ),
    );
  }

  @override
  Future<void> startCapture(void Function(String base64Jpeg) onFrame) async {
    if (!await hasPermission()) {
      debugPrint('[Camera] no camera available');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _isFront = camera.lensDirection == CameraLensDirection.front;

    _controller = CameraController(
      camera,
      ResolutionPreset.low, // 视频通话用低分辨率，减轻转码压力
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // image stream 需 YUV420
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      debugPrint('[Camera] init failed: $e');
      await _controller?.dispose();
      _controller = null;
      return;
    }

    _capturing = true;
    _converting = false;
    _frameSeq = 0;
    _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

    await _controller!.startImageStream((CameraImage image) {
      if (!_capturing || _converting) return;
      final now = DateTime.now();
      if (now.difference(_lastFrame).inMilliseconds < _frameIntervalMs) return;
      _lastFrame = now;
      _converting = true;
      _processFrame(image, onFrame);
    });

    debugPrint('[Camera] Android image stream started, ~0.33fps (low, yuv420)');
  }

  Future<void> _processFrame(
    CameraImage image,
    void Function(String base64Jpeg) onFrame,
  ) async {
    try {
      if (image.planes.length < 3) {
        _converting = false;
        return;
      }
      // 必须同步拷贝：回调返回后底层 buffer 会被 camera 插件复用，
      // compute 异步序列化时若读原 buffer 会拿到脏数据。
      final frame = _YuvFrame(
        width: image.width,
        height: image.height,
        yBytes: Uint8List.fromList(image.planes[0].bytes),
        uBytes: Uint8List.fromList(image.planes[1].bytes),
        vBytes: Uint8List.fromList(image.planes[2].bytes),
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      );
      final jpeg = await compute(_yuvFrameToJpeg, frame);
      _frameSeq++;
      if (_frameSeq <= 3) {
        debugPrint('[Camera] frame #$_frameSeq jpeg=${jpeg.length} bytes');
      }
      if (_capturing) onFrame(base64Encode(jpeg));
    } catch (e) {
      debugPrint('[Camera] convert error: $e');
    } finally {
      _converting = false;
    }
  }

  @override
  Future<void> stopCapture() async {
    _capturing = false;
    _converting = false;
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        await _controller?.stopImageStream();
      }
    } catch (e) {
      debugPrint('[Camera] stopImageStream error: $e');
    }
    try {
      await _controller?.dispose();
    } catch (e) {
      debugPrint('[Camera] dispose error: $e');
    }
    _controller = null;
  }

  @override
  void dispose() {
    stopCapture();
  }
}

/// 可跨 isolate 传输的 YUV420 帧快照（planes 已拷贝为独立副本）。
class _YuvFrame {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  _YuvFrame({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });
}

/// top-level，供 compute() 在独立 isolate 执行：YUV420 → JPEG。
Uint8List _yuvFrameToJpeg(_YuvFrame f) {
  final out = img.Image(width: f.width, height: f.height);
  for (int y = 0; y < f.height; y++) {
    final yRow = y * f.yRowStride;
    final uvRow = (y >> 1) * f.uvRowStride;
    for (int x = 0; x < f.width; x++) {
      final yp = f.yBytes[yRow + x];
      final uvIndex = uvRow + (x >> 1) * f.uvPixelStride;
      final up = f.uBytes[uvIndex];
      final vp = f.vBytes[uvIndex];
      final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
      final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
          .round()
          .clamp(0, 255);
      final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return img.encodeJpg(out, quality: 70);
}
