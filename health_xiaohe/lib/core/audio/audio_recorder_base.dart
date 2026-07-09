// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';

abstract class AudioRecorderBase {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> startRecording(void Function(String base64) onData);
  Future<void> stopRecording();
  void dispose();
  void gateOn() {}   // 压低麦克风，仅通过大声说话
  void gateOff() {}  // 恢复正常收音
  void mute() {}     // 完全静音麦克风（停止发送音频块）
  void unmute() {}   // 恢复发送音频
}
