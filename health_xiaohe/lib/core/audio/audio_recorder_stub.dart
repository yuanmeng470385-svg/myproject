// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Native 平台录音 — 暂未实现，使用 record 包替代
import 'dart:async';
import 'dart:typed_data';
import 'audio_recorder_base.dart';

class AudioRecorder extends AudioRecorderBase {
  @override
  Future<bool> hasPermission() async => false;
  Future<bool> requestPermission() async => false;

  @override
  Future<void> startRecording(void Function(String base64) onData) async {}

  @override
  Future<void> stopRecording() async {}

  @override
  void dispose() {}
}
