// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';

abstract class CameraCaptureBase {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> startCapture(void Function(String base64Jpeg) onFrame);
  Future<void> stopCapture();
  void dispose();
  /// 返回平台预览 widget；不支持平台返回 null
  Widget? buildPreview() => null;
}
