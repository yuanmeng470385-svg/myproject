import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_xiaohe/data/models/agent_step.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';
import 'package:health_xiaohe/data/models/sse_chunk.dart';
import 'package:health_xiaohe/domain/repositories/chat_repository.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_bloc.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_event.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_state.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

void main() {
  late _MockChatRepository repo;

  setUp(() => repo = _MockChatRepository());

  ChatState seedState() => ChatState(messages: [
        ChatMessageModel.user('查血压'),
        ChatMessageModel.assistant(''),
      ]);

  blocTest<ChatBloc, ChatState>(
    'thinking 事件只更新 agentThinking，不动消息',
    build: () => ChatBloc(repo),
    seed: seedState,
    act: (bloc) => bloc.add(ChatReceiveStreamChunk(SseChunk(agentStatus: {
      'type': 'agent_status', 'status': 'thinking', 'content': '正在分析您的问题...',
    }))),
    expect: () => [
      isA<ChatState>()
          .having((s) => s.agentThinking, 'agentThinking', '正在分析您的问题...')
          .having((s) => s.messages.last.agentSteps, 'steps', isNull),
    ],
  );

  blocTest<ChatBloc, ChatState>(
    'tool_call 给流式中消息追加 running 步骤',
    build: () => ChatBloc(repo),
    seed: seedState,
    act: (bloc) => bloc.add(ChatReceiveStreamChunk(SseChunk(agentStatus: {
      'type': 'agent_status', 'status': 'tool_call',
      'tool': 'query_health_records', 'args': {'record_type': 'blood_pressure'},
    }))),
    expect: () => [
      isA<ChatState>().having(
        (s) => s.messages.last.agentSteps!.single,
        'step',
        isA<AgentStep>()
            .having((x) => x.tool, 'tool', 'query_health_records')
            .having((x) => x.isRunning, 'running', true),
      ),
    ],
  );

  blocTest<ChatBloc, ChatState>(
    'tool_result 闭合最后一个同名 running 步骤',
    build: () => ChatBloc(repo),
    seed: () => ChatState(messages: [
      ChatMessageModel.user('查血压'),
      ChatMessageModel.assistant('').copyWith(agentSteps: const [
        AgentStep(tool: 'query_health_records'),
      ]),
    ]),
    act: (bloc) => bloc.add(ChatReceiveStreamChunk(SseChunk(agentStatus: {
      'type': 'agent_status', 'status': 'tool_result',
      'tool': 'query_health_records', 'result': '血压记录（最近 7 天）：...',
    }))),
    expect: () => [
      isA<ChatState>().having(
        (s) => s.messages.last.agentSteps!.single,
        'step',
        isA<AgentStep>()
            .having((x) => x.isRunning, 'running', false)
            .having((x) => x.result, 'result', '血压记录（最近 7 天）：...'),
      ),
    ],
  );

  blocTest<ChatBloc, ChatState>(
    'error 事件置 error 并闭合全部 running 步骤',
    build: () => ChatBloc(repo),
    seed: () => ChatState(messages: [
      ChatMessageModel.user('查血压'),
      ChatMessageModel.assistant('').copyWith(agentSteps: const [
        AgentStep(tool: 'calculator'),
      ]),
    ]),
    act: (bloc) => bloc.add(ChatReceiveStreamChunk(SseChunk(agentStatus: {
      'type': 'agent_status', 'status': 'error', 'content': '处理出错: xxx',
    }))),
    expect: () => [
      isA<ChatState>()
          .having((s) => s.error, 'error', '处理出错: xxx')
          .having((s) => s.messages.last.agentSteps!.single.isRunning, 'running', false),
    ],
  );

  blocTest<ChatBloc, ChatState>(
    'content 帧仍走原有追加逻辑且清空 agentThinking',
    build: () => ChatBloc(repo),
    seed: seedState,
    act: (bloc) => bloc
      ..add(ChatReceiveStreamChunk(SseChunk(agentStatus: {
        'type': 'agent_status', 'status': 'thinking', 'content': '思考中',
      })))
      ..add(ChatReceiveStreamChunk(const SseChunk(content: '您好！'))),
    skip: 1,
    expect: () => [
      isA<ChatState>()
          .having((s) => s.messages.last.content, 'content', '您好！')
          .having((s) => s.agentThinking, 'agentThinking', isNull),
    ],
  );
}
