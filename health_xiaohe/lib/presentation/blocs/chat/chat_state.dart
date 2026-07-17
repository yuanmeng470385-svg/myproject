// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'package:equatable/equatable.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';

class ChatState extends Equatable {
  final List<ChatMessageModel> messages;
  final bool isLoading;
  final bool isStreaming; // AI 流式输出进行中
  final String? error;
  final String? agentThinking; // Agent 思考提示（瞬态：任何 copyWith 不显式携带即清空）
  final String? conversationId;
  final List<String> suggestions; // AI 推荐的追问
  final List<String> welcomeSuggestions; // 欢迎页基于画像生成的快捷问题

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isStreaming = false,
    this.error,
    this.agentThinking,
    this.conversationId,
    this.suggestions = const [],
    this.welcomeSuggestions = const [],
  });

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? isStreaming,
    String? error,
    String? agentThinking,
    String? conversationId,
    List<String>? suggestions,
    List<String>? welcomeSuggestions,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
      agentThinking: agentThinking,
      conversationId: conversationId ?? this.conversationId,
      suggestions: suggestions ?? this.suggestions,
      welcomeSuggestions: welcomeSuggestions ?? this.welcomeSuggestions,
    );
  }

  @override
  List<Object?> get props => [messages, isLoading, isStreaming, error, agentThinking, conversationId, suggestions, welcomeSuggestions];
}
