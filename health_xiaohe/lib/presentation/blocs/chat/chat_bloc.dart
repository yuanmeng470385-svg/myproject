// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_xiaohe/data/models/agent_step.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';
import 'package:health_xiaohe/data/models/sse_chunk.dart';
import 'package:health_xiaohe/domain/repositories/chat_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _chatRepository;
  StreamSubscription<SseChunk>? _streamSubscription;

  // SSE chunk 节流缓冲 — 后端 token 颗粒 ~10-30Hz，每次 emit 都会让 MarkdownBody
  // 重新解析整段文本 + ListView 重建。节流到 ~20Hz 把重解析次数砍 5-10 倍
  String _pendingContent = '';
  Timer? _flushTimer;
  static const _flushInterval = Duration(milliseconds: 50);

  ChatBloc(this._chatRepository) : super(const ChatState()) {
    on<ChatInitialize>(_onInitialize);
    on<ChatLoadWelcomeSuggestions>(_onLoadWelcomeSuggestions);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatReceiveStreamChunk>(_onReceiveChunk);
    on<ChatStreamCompleted>(_onStreamCompleted);
    on<ChatStreamError>(_onStreamError);
    on<ChatClearMessages>(_onClearMessages);
    on<ChatNewConversation>(_onNewConversation);
    on<ChatLoadConversation>(_onLoadConversation);
  }

  void _onInitialize(ChatInitialize event, Emitter<ChatState> emit) {
    if (state.messages.isEmpty) {
      final welcomeMessage = ChatMessageModel.assistant(
        '你好！我是健康小云，你的健康管家~ 有什么健康问题可以问我哦！',
      );
      emit(state.copyWith(messages: [welcomeMessage]));
    }
    add(ChatLoadWelcomeSuggestions());
  }

  Future<void> _onLoadWelcomeSuggestions(
    ChatLoadWelcomeSuggestions event,
    Emitter<ChatState> emit,
  ) async {
    final result = await _chatRepository.getWelcomeSuggestions();
    if (result.success && result.data != null && result.data!.isNotEmpty) {
      emit(state.copyWith(welcomeSuggestions: result.data));
    }
  }

  Future<void> _onSendMessage(
    ChatSendMessage event,
    Emitter<ChatState> emit,
  ) async {
    final imageBytes = event.imageBytes != null ? Uint8List.fromList(event.imageBytes!) : null;
    final userMsg = ChatMessageModel.user(event.message, imageBytes: imageBytes);
    final updatedMessages = [...state.messages, userMsg];
    emit(state.copyWith(messages: updatedMessages, isLoading: true, isStreaming: true, error: null, suggestions: []));

    final assistantMsg = ChatMessageModel.assistant('');
    final messagesWithAssistant = [...updatedMessages, assistantMsg];
    emit(state.copyWith(messages: messagesWithAssistant));

    try {
      final stream = _chatRepository.getChatStream(
        updatedMessages,
        conversationId: state.conversationId,
      );

      _streamSubscription?.cancel();
      _streamSubscription = stream.listen(
        (chunk) {
          // suggestions / conversation_id 立即下发，不积压
          if (!chunk.hasContent) {
            add(ChatReceiveStreamChunk(chunk));
            return;
          }
          _pendingContent += chunk.content!;
          _flushTimer ??= Timer(_flushInterval, _flushPending);
        },
        onError: (error) {
          _flushTimer?.cancel();
          _flushTimer = null;
          _flushPending(); // 出错前把已积压的字推出去
          add(ChatStreamError(error.toString()));
        },
        onDone: () {
          _flushTimer?.cancel();
          _flushTimer = null;
          _flushPending(); // 结束前 flush 剩余内容
          add(ChatStreamCompleted());
        },
      );
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
        messages: updatedMessages,
      ));
    }
  }

  void _onReceiveChunk(ChatReceiveStreamChunk event, Emitter<ChatState> emit) {
    final chunk = event.chunk;

    // Agent 状态事件（必须在 content 之前处理）
    if (chunk.hasAgentStatus) {
      final ev = chunk.agentStatus!;
      final status = ev['status'];
      if (status == 'thinking') {
        emit(state.copyWith(
          messages: state.messages,
          agentThinking: ev['content']?.toString(),
        ));
        return;
      }
      if (status == 'tool_call' || status == 'tool_result') {
        final updated = [...state.messages];
        if (updated.isEmpty || !updated.last.isAssistant) return;
        final last = updated.removeLast();
        final steps = [...(last.agentSteps ?? const <AgentStep>[])];
        if (status == 'tool_call') {
          final rawArgs = ev['args'];
          steps.add(AgentStep(
            tool: ev['tool']?.toString() ?? '',
            args: rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : null,
          ));
        } else {
          final tool = ev['tool']?.toString() ?? '';
          final idx = steps.lastIndexWhere((s) => s.tool == tool && s.isRunning);
          if (idx >= 0) {
            steps[idx] = steps[idx].asDone(ev['result']?.toString() ?? '');
          }
        }
        updated.add(last.copyWith(agentSteps: steps));
        emit(state.copyWith(messages: updated, isLoading: false));
        return;
      }
      if (status == 'error') {
        final updated = [...state.messages];
        if (updated.isNotEmpty && updated.last.isAssistant) {
          final last = updated.removeLast();
          final steps = (last.agentSteps ?? const <AgentStep>[])
              .map((s) => s.isRunning ? s.asDone('') : s)
              .toList();
          updated.add(last.copyWith(agentSteps: steps));
        }
        emit(state.copyWith(
          messages: updated,
          isLoading: false,
          error: ev['content']?.toString() ?? 'Agent 处理出错',
        ));
        return;
      }
      return; // 未知 status 忽略
    }

    // 处理追问建议
    if (chunk.hasSuggestions) {
      emit(state.copyWith(suggestions: chunk.suggestions));
      return;
    }

    // 处理 conversation_id
    if (chunk.hasConversationId && chunk.conversationId != null) {
      emit(state.copyWith(conversationId: chunk.conversationId));
      return;
    }

    // 处理内容追加
    if (chunk.hasContent) {
      final content = chunk.content!;
      final updatedMessages = [...state.messages];
      if (updatedMessages.isNotEmpty && updatedMessages.last.isAssistant) {
        final lastMsg = updatedMessages.removeLast();
        updatedMessages.add(lastMsg.copyWith(content: lastMsg.content + content));
      } else {
        updatedMessages.add(ChatMessageModel.assistant(content));
      }
      emit(state.copyWith(messages: updatedMessages, isLoading: false));
    }
  }

  /// 流中断/结束时闭合最后一条 assistant 消息里仍在 running 的步骤，避免 spinner 永转
  List<ChatMessageModel> _closeRunningSteps(List<ChatMessageModel> messages) {
    if (messages.isEmpty || !messages.last.isAssistant) return messages;
    final last = messages.last;
    final steps = last.agentSteps;
    if (steps == null || !steps.any((s) => s.isRunning)) return messages;
    final closed = steps.map((s) => s.isRunning ? s.asDone('') : s).toList();
    return [...messages.sublist(0, messages.length - 1), last.copyWith(agentSteps: closed)];
  }

  void _onStreamCompleted(ChatStreamCompleted event, Emitter<ChatState> emit) {
    emit(state.copyWith(
      messages: _closeRunningSteps(state.messages),
      isLoading: false,
      isStreaming: false,
    ));
  }

  void _onStreamError(ChatStreamError event, Emitter<ChatState> emit) {
    var messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.isAssistant && messages.last.content.isEmpty) {
      messages.removeLast();
    }
    messages = _closeRunningSteps(messages);
    emit(state.copyWith(messages: messages, isLoading: false, isStreaming: false, error: event.error));
  }

  void _onClearMessages(ChatClearMessages event, Emitter<ChatState> emit) {
    final welcomeMessage = ChatMessageModel.assistant(
      '你好！我是健康小云，你的健康管家~ 有什么健康问题可以问我哦！',
    );
    emit(ChatState(messages: [welcomeMessage]));
  }

  void _onNewConversation(ChatNewConversation event, Emitter<ChatState> emit) {
    final welcomeMessage = ChatMessageModel.assistant(
      '你好！我是健康小云，你的健康管家~ 有什么健康问题可以问我哦！',
    );
    emit(ChatState(messages: [welcomeMessage], suggestions: []));
  }

  Future<void> _onLoadConversation(
    ChatLoadConversation event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    final result = await _chatRepository.getConversationDetail(event.conversationId);
    if (result.success) {
      final detail = result.data!;
      final messages = detail.messages.map((m) {
        return ChatMessageModel(
          role: m.role,
          content: m.content,
          timestamp: m.createdAt,
        );
      }).toList();
      emit(ChatState(
        messages: messages,
        conversationId: event.conversationId,
      ));
    } else {
      emit(state.copyWith(
        isLoading: false,
        error: result.error,
      ));
    }
  }

  void _flushPending() {
    _flushTimer = null;
    if (_pendingContent.isEmpty) return;
    final buffered = _pendingContent;
    _pendingContent = '';
    add(ChatReceiveStreamChunk(SseChunk(content: buffered)));
  }

  @override
  Future<void> close() {
    _flushTimer?.cancel();
    _streamSubscription?.cancel();
    return super.close();
  }
}
