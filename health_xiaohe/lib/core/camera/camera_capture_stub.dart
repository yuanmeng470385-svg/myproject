// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Native 平台摄像头 — 暂未实现
import 'camera_capture_base.dart';

class CameraCapture extends CameraCaptureBase {
  @override
  Future<bool> hasPermission() async => false;
  Future<bool> requestPermission() async => false;

  @override
  Future<void> startCapture(void Function(String base64Jpeg) onFrame) async {}

  @override
  Future<void> stopCapture() async {}

  @override
  void dispose() {}
}
