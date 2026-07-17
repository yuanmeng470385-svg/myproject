// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:health_xiaohe/data/models/agent_step.dart';

class ChatMessageModel {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime? timestamp;
  final Uint8List? imageBytes; // 图片数据
  final List<AgentStep>? agentSteps; // Agent 工具调用步骤（仅会话内，不随 toApiFormat 发送）

  ChatMessageModel({
    required this.role,
    required this.content,
    this.timestamp,
    this.imageBytes,
    this.agentSteps,
  });

  factory ChatMessageModel.user(String content, {Uint8List? imageBytes}) {
    return ChatMessageModel(
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
      imageBytes: imageBytes,
    );
  }

  factory ChatMessageModel.assistant(String content) {
    return ChatMessageModel(
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
    );
  }

  factory ChatMessageModel.system(String content) {
    return ChatMessageModel(
      role: 'system',
      content: content,
      timestamp: DateTime.now(),
    );
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';
  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;

  Map<String, dynamic> toApiFormat() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (hasImage) {
      map['image'] = base64Encode(imageBytes!);
    }
    return map;
  }

  ChatMessageModel copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    Uint8List? imageBytes,
    List<AgentStep>? agentSteps,
  }) {
    return ChatMessageModel(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      imageBytes: imageBytes ?? this.imageBytes,
      agentSteps: agentSteps ?? this.agentSteps,
    );
  }
}
