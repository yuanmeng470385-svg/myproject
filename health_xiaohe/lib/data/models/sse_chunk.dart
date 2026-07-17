// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
class SseChunk {
  final String? content;
  final String? conversationId;
  final List<String>? suggestions;
  final Map<String, dynamic>? agentStatus; // agent_status 事件原始 map

  const SseChunk({this.content, this.conversationId, this.suggestions, this.agentStatus});

  bool get hasContent => content != null && content!.isNotEmpty;
  bool get hasConversationId => conversationId != null && conversationId!.isNotEmpty;
  bool get hasSuggestions => suggestions != null && suggestions!.isNotEmpty;
  bool get hasAgentStatus => agentStatus != null;

  /// 把一个 SSE data JSON 解析为 0..n 个 SseChunk。
  /// 硬性规则：先判 type == 'agent_status' 再判 content ——
  /// thinking 事件也带 content 字段，判反了思考文案会被拼进回答气泡。
  static List<SseChunk> fromEventJson(Map<String, dynamic> json) {
    if (json['type'] == 'agent_status') {
      return [SseChunk(agentStatus: json)];
    }
    final chunks = <SseChunk>[];
    final suggestions = json['suggestions'];
    if (suggestions != null && suggestions is List) {
      chunks.add(SseChunk(suggestions: suggestions.cast<String>()));
    }
    final content = json['content'];
    if (content != null && content.toString().isNotEmpty) {
      chunks.add(SseChunk(content: content.toString()));
    }
    final convId = json['conversation_id'];
    if (convId != null && convId.toString().isNotEmpty) {
      chunks.add(SseChunk(conversationId: convId.toString()));
    }
    return chunks;
  }
}
