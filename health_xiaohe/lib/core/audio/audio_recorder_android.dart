// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Android 平台录音 — MethodChannel 直连原生 AudioRecord + 硬件回声消除
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'audio_recorder_base.dart';

class AudioRecorder extends AudioRecorderBase {
  static const _channel = MethodChannel('com.healthxiaohe/audio_recorder');
  StreamSubscription<Uint8List>? _sub;
  bool _gate = false; // true=压低麦克风，仅通过大声说话
  bool _muted = false; // true=完全静音，不发送任何音频

  void gateOn() => _gate = true;
  void gateOff() => _gate = false;
  void mute() => _muted = true;
  void unmute() => _muted = false;

  @override
  Future<bool> hasPermission() async {
    try {
      await _channel.invokeMethod('start', {'sampleRate': 16000});
      await _channel.invokeMethod('stop');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startRecording(void Function(String base64) onData) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onAudio') return;
      final bytes = call.arguments as Uint8List;
      if (bytes.isEmpty) return;

      // 完全静音模式 — AI说话时阻止回声循环
      if (_muted) return;

      // 噪声门：压低模式下只通过大声说话，过滤音箱回声
      if (_gate && !_isLoud(bytes)) return;

      onData(base64Encode(bytes));
    });
    await _channel.invokeMethod('start', {'sampleRate': 16000});
  }

  bool _isLoud(Uint8List pcm) {
    // 步进采样而非逐样本遍历：门限判断不需要精确峰值，每 8 个样本取一个，
    // 把 AI 说话期间这段 UI isolate 的 CPU 开销降一个数量级（避免和涟漪动画抢帧）。
    final view = ByteData.view(pcm.buffer, pcm.offsetInBytes, pcm.length);
    var peak = 0;
    const stride = 16; // 8 个 16-bit 样本
    for (var i = 0; i + 1 < pcm.length; i += stride) {
      final s = view.getInt16(i, Endian.little).abs();
      if (s > peak) {
        peak = s;
        if (peak > 800) return true; // 提前退出，无需扫完整块
      }
    }
    return peak > 800; // 正常说话约 2.5% 最大振幅，滤除底噪即可
  }

  @override
  Future<void> stopRecording() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('stop');
  }

  @override
  void dispose() {
    stopRecording();
  }
}
