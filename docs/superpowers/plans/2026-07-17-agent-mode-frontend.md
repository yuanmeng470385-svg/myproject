# Agent 模式前端接入实施计划（Flutter + xiaohe-web）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 两端聊天页默认启用后端 Agent 模式，把工具调用过程渲染为消息气泡内的可折叠步骤卡片。

**Architecture:** 后端零改动。Flutter 端把 SSE 帧解析收敛到 `SseChunk.fromEventJson()` 单点（同时修"thinking 的 content 污染气泡"问题），步骤数据挂在 `ChatMessageModel.agentSteps`，由 ChatBloc 按映射规则维护，新组件 `AgentStepsCard` 渲染。Vue 端在 `chat.ts` 解析分支最前加 `agent_status` 判断并透传 `onAgentStatus` 回调，`ChatPage.vue` 在 reactive 消息对象上维护 `steps` 数组并渲染。

**Tech Stack:** Flutter (flutter_bloc, bloc_test, mocktail) / Vue 3 + TS (vite, vue-tsc)。无新增依赖。

**设计依据:** `docs/superpowers/specs/2026-07-17-agent-mode-frontend-design.md`（协议契约、事件映射规则、UI 规范以 spec 为准）

## Global Constraints

- 仓库：`d:/gongsi/app`，分支 `feat/visual-redesign`；工作区有他人未提交改动，**只 `git add` 本计划涉及的文件，禁止 `git add -A`**
- git 身份未配置，提交统一用：`git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "..."`
- Flutter 新增 UI 一律引用 token（`AppColors`/`AppRadius`/`AppMotion`/`AppShadows`），禁止裸 hex
- 项目源文件头部有「AI 生成」注释横幅约定，新建 Dart 文件保持同样式
- 文案全部简体中文
- SSE 解析硬性规则：**先判 `type == 'agent_status'` 再判 `content`**（thinking 事件也带 content 字段）
- 工具中文标签（两端各一份常量）：query_health_records→查询健康记录、get_latest_health_records→获取最新记录、analyze_health_trend→趋势分析、get_user_profile_summary→读取健康画像、calculator→计算、get_current_datetime→获取时间；未知名回退原名
- Flutter 命令在 `health_xiaohe/` 下执行；Vue 命令在 `xiaohe-web/` 下执行

---

### Task 1: Flutter AgentStep 模型 + 工具标签

**Files:**
- Create: `health_xiaohe/lib/data/models/agent_step.dart`
- Test: `health_xiaohe/test/data/models/agent_step_test.dart`

**Interfaces:**
- Produces: `class AgentStep { final String tool; final Map<String, dynamic>? args; final String? result; final bool isRunning; }`，构造 `AgentStep({required tool, args, result, isRunning = true})`，方法 `AgentStep asDone(String result)`，getter `String get label`；常量 `const Map<String, String> kAgentToolLabels`

- [ ] **Step 1: 写失败测试**

```dart
// health_xiaohe/test/data/models/agent_step_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:health_xiaohe/data/models/agent_step.dart';

void main() {
  test('新建步骤默认 running', () {
    const step = AgentStep(tool: 'calculator', args: {'expression': '1+1'});
    expect(step.isRunning, true);
    expect(step.result, isNull);
  });

  test('asDone 返回已完成副本且保留 tool/args', () {
    const step = AgentStep(tool: 'calculator', args: {'expression': '1+1'});
    final done = step.asDone('计算结果: 1+1 = 2');
    expect(done.isRunning, false);
    expect(done.result, '计算结果: 1+1 = 2');
    expect(done.tool, 'calculator');
    expect(done.args, {'expression': '1+1'});
    expect(step.isRunning, true); // 原对象不可变
  });

  test('label 映射中文，未知工具回退原名', () {
    expect(const AgentStep(tool: 'query_health_records').label, '查询健康记录');
    expect(const AgentStep(tool: 'analyze_health_trend').label, '趋势分析');
    expect(const AgentStep(tool: 'unknown_tool').label, 'unknown_tool');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd health_xiaohe && flutter test test/data/models/agent_step_test.dart`
Expected: FAIL（`agent_step.dart` 不存在，编译错误）

- [ ] **Step 3: 实现模型**

```dart
// health_xiaohe/lib/data/models/agent_step.dart
// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================

/// Agent 工具调用步骤 —— 挂在 ChatMessageModel.agentSteps 上，仅会话内存活（不持久化）
class AgentStep {
  final String tool;
  final Map<String, dynamic>? args;
  final String? result;
  final bool isRunning;

  const AgentStep({
    required this.tool,
    this.args,
    this.result,
    this.isRunning = true,
  });

  /// 收到 tool_result 后生成的已完成副本
  AgentStep asDone(String result) =>
      AgentStep(tool: tool, args: args, result: result, isRunning: false);

  /// 中文标签，未知工具名回退原名
  String get label => kAgentToolLabels[tool] ?? tool;
}

/// 工具名 → 中文标签（与 backend/agents/tools/ 注册的 6 个工具对应）
const Map<String, String> kAgentToolLabels = {
  'query_health_records': '查询健康记录',
  'get_latest_health_records': '获取最新记录',
  'analyze_health_trend': '趋势分析',
  'get_user_profile_summary': '读取健康画像',
  'calculator': '计算',
  'get_current_datetime': '获取时间',
};
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd health_xiaohe && flutter test test/data/models/agent_step_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 5: Commit**

```bash
cd d:/gongsi/app
git add health_xiaohe/lib/data/models/agent_step.dart health_xiaohe/test/data/models/agent_step_test.dart
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(flutter): AgentStep 模型与工具中文标签"
```

---

### Task 2: Flutter SSE 解析收敛到 SseChunk.fromEventJson（含 agent_status）

三处重复的"JSON→SseChunk"逻辑（sse_client_stub 一处、sse_client_web 两处）收敛为单一静态方法，agent_status 判断只写一次、可单测。

**Files:**
- Modify: `health_xiaohe/lib/data/models/sse_chunk.dart`
- Modify: `health_xiaohe/lib/core/network/sse_client_stub.dart:37-51`
- Modify: `health_xiaohe/lib/core/network/sse_client_web.dart:47-62, 78-95`
- Test: `health_xiaohe/test/data/models/sse_chunk_test.dart`

**Interfaces:**
- Consumes: 无（独立于 Task 1）
- Produces: `SseChunk` 新增 `final Map<String, dynamic>? agentStatus;` + `bool get hasAgentStatus`；静态方法 `static List<SseChunk> fromEventJson(Map<String, dynamic> json)`（Task 4 的 Bloc 消费 `agentStatus`）

- [ ] **Step 1: 写失败测试**

```dart
// health_xiaohe/test/data/models/sse_chunk_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:health_xiaohe/data/models/sse_chunk.dart';

void main() {
  test('agent_status thinking 事件：只产出 agentStatus，不产出 content（防污染回归）', () {
    final chunks = SseChunk.fromEventJson({
      'type': 'agent_status',
      'status': 'thinking',
      'content': '正在分析您的问题...',
    });
    expect(chunks.length, 1);
    expect(chunks.single.hasAgentStatus, true);
    expect(chunks.single.hasContent, false);
    expect(chunks.single.agentStatus!['status'], 'thinking');
  });

  test('agent_status tool_call/tool_result 事件透传原始 map', () {
    final call = SseChunk.fromEventJson({
      'type': 'agent_status', 'status': 'tool_call',
      'tool': 'calculator', 'args': {'expression': '1+1'},
    });
    expect(call.single.agentStatus!['tool'], 'calculator');

    final result = SseChunk.fromEventJson({
      'type': 'agent_status', 'status': 'tool_result',
      'tool': 'calculator', 'result': '计算结果: 1+1 = 2',
    });
    expect(result.single.agentStatus!['result'], '计算结果: 1+1 = 2');
  });

  test('普通 content 帧行为不变', () {
    final chunks = SseChunk.fromEventJson({'content': '你好'});
    expect(chunks.length, 1);
    expect(chunks.single.content, '你好');
    expect(chunks.single.hasAgentStatus, false);
  });

  test('conversation_id / suggestions 帧行为不变', () {
    expect(SseChunk.fromEventJson({'conversation_id': 'abc'}).single.conversationId, 'abc');
    expect(SseChunk.fromEventJson({'suggestions': ['a', 'b']}).single.suggestions, ['a', 'b']);
  });

  test('空 content 不产出 chunk', () {
    expect(SseChunk.fromEventJson({'content': ''}), isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd health_xiaohe && flutter test test/data/models/sse_chunk_test.dart`
Expected: FAIL（`fromEventJson` 未定义）

- [ ] **Step 3: 改 sse_chunk.dart（全文替换 class 体）**

```dart
// health_xiaohe/lib/data/models/sse_chunk.dart
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
```

- [ ] **Step 4: sse_client_stub.dart 改用 fromEventJson**

把 37-51 行的 try 块内容替换为：

```dart
            try {
              final json = jsonDecode(data);
              if (json is Map<String, dynamic>) {
                for (final c in SseChunk.fromEventJson(json)) {
                  controller.add(c);
                }
              }
            } catch (_) {}
```

- [ ] **Step 5: sse_client_web.dart 两处解析同步替换**

第一处（`processIncremental` 内 47-62 行的 try 块）替换为：

```dart
      try {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          for (final c in SseChunk.fromEventJson(json)) {
            controller.add(c);
          }
        }
      } catch (_) {}
```

第二处（`onReadyStateChange` 内 78-95 行处理残留行的 try 块）替换为：

```dart
          try {
            final json = jsonDecode(data);
            if (json is Map<String, dynamic>) {
              for (final c in SseChunk.fromEventJson(json)) {
                controller.add(c);
              }
            }
          } catch (_) {}
```

- [ ] **Step 6: 跑测试 + 静态检查**

Run: `cd health_xiaohe && flutter test test/data/models/sse_chunk_test.dart && flutter analyze lib/data/models/sse_chunk.dart lib/core/network/sse_client_stub.dart lib/core/network/sse_client_web.dart`
Expected: 测试 PASS（5 tests），analyze 无新 error

- [ ] **Step 7: Commit**

```bash
cd d:/gongsi/app
git add health_xiaohe/lib/data/models/sse_chunk.dart health_xiaohe/lib/core/network/sse_client_stub.dart health_xiaohe/lib/core/network/sse_client_web.dart health_xiaohe/test/data/models/sse_chunk_test.dart
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(flutter): SSE 解析收敛 fromEventJson，识别 agent_status 事件"
```

---

### Task 3: Flutter 消息模型挂步骤 + 请求开启 agent_mode

**Files:**
- Modify: `health_xiaohe/lib/data/models/chat_message_model.dart`
- Modify: `health_xiaohe/lib/data/repositories/chat_repository_impl.dart:26-29`
- Test: `health_xiaohe/test/data/models/chat_message_model_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `AgentStep`
- Produces: `ChatMessageModel` 新增 `final List<AgentStep>? agentSteps;`（构造参数 + `copyWith({List<AgentStep>? agentSteps})`）；`toApiFormat()` **不含** agentSteps

- [ ] **Step 1: 写失败测试**

```dart
// health_xiaohe/test/data/models/chat_message_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:health_xiaohe/data/models/agent_step.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';

void main() {
  test('copyWith 可携带 agentSteps 且不影响原对象', () {
    final msg = ChatMessageModel.assistant('回答');
    final withSteps = msg.copyWith(agentSteps: const [AgentStep(tool: 'calculator')]);
    expect(withSteps.agentSteps!.length, 1);
    expect(withSteps.content, '回答');
    expect(msg.agentSteps, isNull);
  });

  test('toApiFormat 不包含 agentSteps', () {
    final msg = ChatMessageModel.assistant('回答')
        .copyWith(agentSteps: const [AgentStep(tool: 'calculator')]);
    expect(msg.toApiFormat().containsKey('agentSteps'), false);
    expect(msg.toApiFormat(), {'role': 'assistant', 'content': '回答'});
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd health_xiaohe && flutter test test/data/models/chat_message_model_test.dart`
Expected: FAIL（`agentSteps` 参数未定义）

- [ ] **Step 3: 改 chat_message_model.dart**

顶部加 import：`import 'package:health_xiaohe/data/models/agent_step.dart';`

字段区（`final Uint8List? imageBytes;` 之后）加：

```dart
  final List<AgentStep>? agentSteps; // Agent 工具调用步骤（仅会话内，不随 toApiFormat 发送）
```

构造函数加可选参数 `this.agentSteps,`（三个 factory 不变——新消息无步骤）。

`copyWith` 加参数与赋值：

```dart
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
```

`toApiFormat()` 不动。

- [ ] **Step 4: chat_repository_impl.dart 请求体加 agent_mode**

26-29 行 body 改为：

```dart
    final body = <String, dynamic>{
      'messages': apiMessages,
      'agent_mode': true, // Agent 模式默认全开，是否调工具由 AI 决定
      if (conversationId != null) 'conversation_id': conversationId,
    };
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd health_xiaohe && flutter test test/data/models/chat_message_model_test.dart`
Expected: PASS（2 tests）

- [ ] **Step 6: Commit**

```bash
cd d:/gongsi/app
git add health_xiaohe/lib/data/models/chat_message_model.dart health_xiaohe/lib/data/repositories/chat_repository_impl.dart health_xiaohe/test/data/models/chat_message_model_test.dart
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(flutter): 消息模型挂 agentSteps，聊天请求默认 agent_mode"
```

---

### Task 4: Flutter ChatBloc 分发 agent_status

**Files:**
- Modify: `health_xiaohe/lib/presentation/blocs/chat/chat_state.dart`
- Modify: `health_xiaohe/lib/presentation/blocs/chat/chat_bloc.dart`
- Test: `health_xiaohe/test/presentation/blocs/chat_bloc_agent_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 `AgentStep`、Task 2 `SseChunk.agentStatus`、Task 3 `ChatMessageModel.agentSteps`
- Produces: `ChatState` 新增 `final String? agentThinking;`（**瞬态字段**：copyWith 不传即清空，同 `error` 模式）；Bloc 行为——tool_call 给流式中消息追加 running 步骤 / tool_result 闭合最后一个同名 running 步骤 / thinking 只设 agentThinking / error 置 state.error 并闭合全部 running 步骤

- [ ] **Step 1: 写失败测试**

```dart
// health_xiaohe/test/presentation/blocs/chat_bloc_agent_test.dart
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd health_xiaohe && flutter test test/presentation/blocs/chat_bloc_agent_test.dart`
Expected: FAIL（`agentThinking` 未定义）

- [ ] **Step 3: chat_state.dart 加瞬态字段**

字段区加 `final String? agentThinking; // Agent 思考提示（瞬态：任何 copyWith 不显式携带即清空）`；构造函数加 `this.agentThinking,`；`copyWith` 参数加 `String? agentThinking,`、赋值用**直传**（同 error 模式）：`agentThinking: agentThinking,`；`props` 追加 `agentThinking`。

- [ ] **Step 4: chat_bloc.dart 加分发逻辑**

顶部加 import：`import 'package:health_xiaohe/data/models/agent_step.dart';`

`_onReceiveChunk` 方法体最前面（`final chunk = event.chunk;` 之后）插入：

```dart
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
```

注意：thinking 分支的 `copyWith` 显式带 `messages: state.messages` 只是沿用引用（`buildWhen` 的 `identical` 检查不会误触发列表重建）；content 分支**不用改**——瞬态 copyWith 自动清掉 agentThinking。

- [ ] **Step 5: 跑测试确认通过 + 回归**

Run: `cd health_xiaohe && flutter test test/presentation/blocs/chat_bloc_agent_test.dart && flutter test`
Expected: 新增 5 tests PASS；全量无回归

- [ ] **Step 6: Commit**

```bash
cd d:/gongsi/app
git add health_xiaohe/lib/presentation/blocs/chat/chat_state.dart health_xiaohe/lib/presentation/blocs/chat/chat_bloc.dart health_xiaohe/test/presentation/blocs/chat_bloc_agent_test.dart
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(flutter): ChatBloc 分发 agent_status（步骤/思考/错误）"
```

---

### Task 5: Flutter AgentStepsCard 组件 + 气泡集成

**Files:**
- Create: `health_xiaohe/lib/presentation/widgets/chat/agent_steps_card.dart`
- Modify: `health_xiaohe/lib/presentation/widgets/chat/message_bubble.dart`
- Modify: `health_xiaohe/lib/presentation/pages/chat/chat_home_page.dart:148-190`

**Interfaces:**
- Consumes: Task 1 `AgentStep`（`.label`/`.isRunning`/`.result`）、Task 4 `ChatState.agentThinking`
- Produces: `AgentStepsCard({required List<AgentStep> steps, required bool isStreaming})`；`MessageBubble`/`AiMessageBubble` 新增可选参数 `String? thinkingText`

- [ ] **Step 1: 新建 agent_steps_card.dart**

```dart
// health_xiaohe/lib/presentation/widgets/chat/agent_steps_card.dart
// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'package:flutter/material.dart';
import 'package:health_xiaohe/core/constants/app_colors.dart';
import 'package:health_xiaohe/core/constants/app_motion.dart';
import 'package:health_xiaohe/core/constants/app_radius.dart';
import 'package:health_xiaohe/data/models/agent_step.dart';

/// Agent 工具调用步骤卡片：流式中逐条展示（转圈→✓），
/// 完成后折叠为"已调用 N 个工具"摘要行，点开可看每步的原始返回。
class AgentStepsCard extends StatefulWidget {
  final List<AgentStep> steps;
  final bool isStreaming;

  const AgentStepsCard({super.key, required this.steps, required this.isStreaming});

  @override
  State<AgentStepsCard> createState() => _AgentStepsCardState();
}

class _AgentStepsCardState extends State<AgentStepsCard> {
  bool? _expanded; // null = 自动（流式中展开，完成后折叠）
  final Set<int> _openResults = {};

  bool get _isExpanded => _expanded ?? widget.isStreaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: AnimatedSize(
        duration: AppMotion.fast,
        curve: AppMotion.calm,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 摘要行（流式中不可折叠，完成后可点击开合）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.isStreaming
                  ? null
                  : () => setState(() => _expanded = !_isExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_circle_outlined, size: 15, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    widget.isStreaming ? '正在调用工具' : '已调用 ${widget.steps.length} 个工具',
                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                  if (!widget.isStreaming) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 6),
              for (var i = 0; i < widget.steps.length; i++) _buildStepRow(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(int i) {
    final step = widget.steps[i];
    final resultOpen = _openResults.contains(i);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: step.result == null || step.result!.isEmpty
                ? null
                : () => setState(() {
                      resultOpen ? _openResults.remove(i) : _openResults.add(i);
                    }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                step.isRunning
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(Icons.check_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  step.label,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (resultOpen)
            Container(
              margin: const EdgeInsets.only(left: 20, top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                step.result!,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textTertiary,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: message_bubble.dart 集成**

顶部加 import：

```dart
import 'package:health_xiaohe/presentation/widgets/chat/agent_steps_card.dart';
```

`MessageBubble` 加可选参数并透传：

```dart
class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isStreaming;
  final String? thinkingText;

  const MessageBubble({super.key, required this.message, this.isStreaming = false, this.thinkingText});
```

（build 内 `AiMessageBubble(message: message, isStreaming: isStreaming, thinkingText: thinkingText)`）

`AiMessageBubble` 同样加 `final String? thinkingText;` 构造参数。其 build 中气泡 `Column` 的 children 改为（在原 `if (message.content.isNotEmpty)` 之前插入两段）：

```dart
                children: [
                  // Agent 工具调用步骤卡片
                  if (message.agentSteps != null && message.agentSteps!.isNotEmpty)
                    AgentStepsCard(
                      steps: message.agentSteps!,
                      isStreaming: isStreaming,
                    ),
                  // Agent 思考提示（仅内容尚未到达时）
                  if (isStreaming && message.content.isEmpty && thinkingText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        thinkingText!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  if (message.content.isNotEmpty)
                    // ……（原有内容渲染不动）
```

- [ ] **Step 3: chat_home_page.dart 传 thinkingText + buildWhen 补条件**

`buildWhen`（148-151 行）追加一个条件：

```dart
              buildWhen: (prev, cur) =>
                  !identical(prev.messages, cur.messages) ||
                  prev.isStreaming != cur.isStreaming ||
                  prev.isLoading != cur.isLoading ||
                  prev.agentThinking != cur.agentThinking,
```

流式气泡分支（188-190 行）改为：

```dart
                    return RepaintBoundary(
                      child: MessageBubble(
                        message: msg,
                        isStreaming: streaming,
                        thinkingText: streaming ? state.agentThinking : null,
                      ),
                    );
```

（182-186 行已完成气泡的缓存分支不动——完成后无 thinking。）

- [ ] **Step 4: 静态检查 + 全量测试**

Run: `cd health_xiaohe && flutter analyze lib/presentation/widgets/chat/ lib/presentation/pages/chat/chat_home_page.dart && flutter test`
Expected: analyze 无新 error；全量测试 PASS

- [ ] **Step 5: Commit**

```bash
cd d:/gongsi/app
git add health_xiaohe/lib/presentation/widgets/chat/agent_steps_card.dart health_xiaohe/lib/presentation/widgets/chat/message_bubble.dart health_xiaohe/lib/presentation/pages/chat/chat_home_page.dart
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(flutter): Agent 步骤卡片组件与气泡集成"
```

---

### Task 6: Vue chat.ts 协议层

**Files:**
- Modify: `xiaohe-web/src/services/chat.ts`

**Interfaces:**
- Produces:
  - `export interface AgentStatusEvent { status: "thinking" | "tool_call" | "tool_result" | "error"; content?: string; tool?: string; args?: Record<string, unknown>; result?: string; }`
  - `export interface AgentStep { tool: string; args?: Record<string, unknown>; result: string | null; running: boolean; open?: boolean; }`
  - `export const AGENT_TOOL_LABELS: Record<string, string>`
  - `StreamCallbacks` 新增 `onAgentStatus?: (ev: AgentStatusEvent) => void;`
  - 请求体新增 `agent_mode: true`

- [ ] **Step 1: 加类型与常量**

在 `ChatMessage` 接口之后插入：

```typescript
/** agent_status SSE 事件（后端 agents/streaming.py 定义） */
export interface AgentStatusEvent {
  status: "thinking" | "tool_call" | "tool_result" | "error";
  content?: string;
  tool?: string;
  args?: Record<string, unknown>;
  result?: string;
}

/** 工具调用步骤（挂在页面消息对象上，仅会话内存活） */
export interface AgentStep {
  tool: string;
  args?: Record<string, unknown>;
  result: string | null;
  running: boolean;
  /** 是否展开原始返回 */
  open?: boolean;
}

/** 工具名 → 中文标签（与后端 6 个注册工具对应，未知名回退原名） */
export const AGENT_TOOL_LABELS: Record<string, string> = {
  query_health_records: "查询健康记录",
  get_latest_health_records: "获取最新记录",
  analyze_health_trend: "趋势分析",
  get_user_profile_summary: "读取健康画像",
  calculator: "计算",
  get_current_datetime: "获取时间",
};
```

`StreamCallbacks` 接口加一行（`onChunk` 之前）：

```typescript
  /** agent_status event: thinking / tool_call / tool_result / error */
  onAgentStatus?: (ev: AgentStatusEvent) => void;
```

- [ ] **Step 2: 请求体加 agent_mode**

`body: JSON.stringify({...})` 改为：

```typescript
      body: JSON.stringify({
        messages,
        stream: true,
        agent_mode: true, // Agent 模式默认全开，是否调工具由 AI 决定
        conversation_id: conversationId ?? null,
      }),
```

- [ ] **Step 3: 解析分支最前加 agent_status（硬性规则：先判 type 再判 content）**

`const obj = JSON.parse(payload);` 之后的分发改为：

```typescript
            const obj = JSON.parse(payload);
            // agent_status 必须最先判断：thinking 事件也带 content 字段，
            // 落到下面的 content 分支会把思考文案拼进回答
            if (obj && obj.type === "agent_status") {
              cb.onAgentStatus?.(obj as AgentStatusEvent);
            } else if (typeof obj.content === "string") {
              full += obj.content;
              cb.onChunk?.(obj.content);
            } else if (typeof obj.conversation_id === "string") {
              convoId = obj.conversation_id;
              cb.onConversationId?.(obj.conversation_id);
            } else if (Array.isArray(obj.suggestions)) {
              cb.onSuggestions?.(obj.suggestions);
            }
```

同时更新文件头部的帧格式注释（29 行 doc comment），补一行：

```
 *   { type: "agent_status", status, ... }     — agent tool activity
```

- [ ] **Step 4: 类型检查**

Run: `cd xiaohe-web && npx vue-tsc -b`
Expected: 无错误

- [ ] **Step 5: Commit**

```bash
cd d:/gongsi/app
git add xiaohe-web/src/services/chat.ts
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(web): chat 协议层支持 agent_mode 与 agent_status 事件"
```

---

### Task 7: Vue ChatPage 步骤卡片

**Files:**
- Modify: `xiaohe-web/src/pages/ChatPage.vue`

**Interfaces:**
- Consumes: Task 6 的 `AgentStatusEvent` / `AgentStep` / `AGENT_TOOL_LABELS` / `onAgentStatus`
- Produces: `UIMsg` 新增 `steps?: AgentStep[]; thinkingText?: string; stepsOpen?: boolean;`

- [ ] **Step 1: script 改动**

import 行改为：

```typescript
import { streamChat, AGENT_TOOL_LABELS, type AgentStep, type ChatMessage } from "../services/chat";
```

`UIMsg` 接口加三个字段（`streaming?: boolean;` 之后）：

```typescript
  /** agent tool-call steps (session-only, not persisted) */
  steps?: AgentStep[];
  /** transient thinking hint from agent_status */
  thinkingText?: string;
  /** steps panel expanded after completion (during receiving it's always open) */
  stepsOpen?: boolean;
```

`send()` 里 `aiMsg` 的 reactive 初始化加两个字段：

```typescript
  const aiMsg = reactive<UIMsg>({
    id: nextId(),
    role: "assistant",
    content: "",
    fullContent: "",
    receiving: true,
    streaming: true,
    steps: [],
    thinkingText: "",
  });
```

`streamChat` 回调对象里（`onChunk` 之前）加：

```typescript
      onAgentStatus: (ev) => {
        if (ev.status === "thinking") {
          aiMsg.thinkingText = ev.content || "";
        } else if (ev.status === "tool_call") {
          aiMsg.steps!.push({
            tool: ev.tool ?? "",
            args: ev.args,
            result: null,
            running: true,
          });
        } else if (ev.status === "tool_result") {
          // 闭合最后一个同名 running 步骤
          const steps = aiMsg.steps ?? [];
          for (let i = steps.length - 1; i >= 0; i--) {
            if (steps[i].running && steps[i].tool === ev.tool) {
              steps[i].result = ev.result ?? "";
              steps[i].running = false;
              break;
            }
          }
        } else if (ev.status === "error") {
          aiMsg.steps?.forEach((s) => (s.running = false));
          errorMsg.value = ev.content || "Agent 处理出错";
        }
      },
```

script 里加一个工具函数（`nextId` 之后）：

```typescript
const toolLabel = (t: string) => AGENT_TOOL_LABELS[t] ?? t;
```

- [ ] **Step 2: 模板改动**

`.content` div 整体替换为：

```html
          <div class="content">
            <template v-if="m.role === 'assistant'">
              <!-- agent tool-call steps -->
              <div v-if="m.steps && m.steps.length" class="agent-steps">
                <button
                  v-if="!m.receiving"
                  class="steps-summary"
                  @click="m.stepsOpen = !m.stepsOpen"
                  data-hover
                >
                  ⚙ 已调用 {{ m.steps.length }} 个工具
                  <span class="chev">{{ m.stepsOpen ? "▴" : "▾" }}</span>
                </button>
                <span v-else class="steps-summary passive">⚙ 正在调用工具</span>
                <ul v-if="m.receiving || m.stepsOpen" class="steps-list">
                  <li v-for="(s, si) in m.steps" :key="si" class="step">
                    <button class="step-row" @click="s.open = !s.open" data-hover>
                      <span v-if="s.running" class="step-spin" aria-hidden="true"></span>
                      <span v-else class="step-check">✓</span>
                      <span class="step-label">{{ toolLabel(s.tool) }}</span>
                    </button>
                    <pre v-if="s.open && s.result" class="step-result">{{ s.result }}</pre>
                  </li>
                </ul>
              </div>
              <span v-if="!m.content && m.streaming" class="thinking italic-en">
                {{ m.thinkingText || "正在听你说的话…" }}
              </span>
              <template v-else>
                <span class="md" v-html="renderMarkdown(m.content)"></span><span v-if="m.streaming" class="caret">▍</span>
              </template>
            </template>
            <template v-else>{{ m.content }}</template>
          </div>
```

- [ ] **Step 3: scoped 样式（加在 `.thinking` 规则之后）**

```css
/* agent tool-call steps */
.agent-steps {
  margin-bottom: 0.6rem;
  padding: 0.5rem 0.7rem;
  background: rgba(168, 216, 197, 0.14);
  border: 1px solid rgba(107, 143, 122, 0.16);
  border-radius: 0.8rem;
}
.steps-summary {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.78rem;
  letter-spacing: 0.06em;
  color: var(--ink-quiet);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
}
.steps-summary.passive { cursor: default; }
.steps-summary .chev { font-size: 0.7rem; }
.steps-list {
  list-style: none;
  margin: 0.4rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}
.step-row {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.85rem;
  color: var(--ink);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
}
.step-check { color: var(--sage-deep); font-size: 0.8rem; }
.step-spin {
  width: 0.7rem; height: 0.7rem;
  border: 2px solid rgba(107, 143, 122, 0.25);
  border-top-color: var(--sage-deep);
  border-radius: 50%;
  animation: step-spin 0.8s linear infinite;
}
@keyframes step-spin { to { transform: rotate(360deg); } }
.step-result {
  margin: 0.3rem 0 0 1.15rem;
  padding: 0.5rem 0.7rem;
  font-family: var(--font-mono);
  font-size: 0.72rem;
  line-height: 1.6;
  color: var(--ink-quiet);
  background: rgba(255, 255, 255, 0.6);
  border-radius: 0.5rem;
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 12rem;
  overflow-y: auto;
}
```

- [ ] **Step 4: 构建验证**

Run: `cd xiaohe-web && npm run build`
Expected: vue-tsc + vite build 均通过

- [ ] **Step 5: Commit**

```bash
cd d:/gongsi/app
git add xiaohe-web/src/pages/ChatPage.vue
git -c user.name="peter mei" -c user.email="sai828160@qq.com" commit -m "feat(web): 聊天页 Agent 步骤卡片（实时+可折叠）"
```

---

### Task 8: 端到端验收（spec §8）

**Files:** 无代码改动；验证 Task 1-7 的集成效果

- [ ] **Step 1: 起后端**

Run: `cd d:/gongsi/app/backend && python -m uvicorn main:app --host 127.0.0.1 --port 8002`（后台）
Expected: `curl http://127.0.0.1:8002/health` 返回 `{"status":"healthy"}`

- [ ] **Step 2: Vue 端验收**

Run: `cd xiaohe-web && npm run dev`，浏览器登录后逐条验证：
1. 问"帮我分析最近的血压趋势" → 步骤卡片逐条出现（转圈→✓）→ 最终回答含真实数据 → 完成后折叠为"⚙ 已调用 N 个工具"，点开可看步骤和原始返回
2. 问"你好" → 无步骤卡片，行为与改动前一致
3. 再发一条消息后回滚看第 1 条 → 步骤仍可展开

- [ ] **Step 3: Flutter 端验收**

Run: `cd health_xiaohe && flutter run --dart-define=API_HOST=localhost -d chrome`，同样跑上面 3 条。
（Android 真机/模拟器可选加测：`flutter run --dart-define=API_HOST=<局域网IP> -d <device>`；Android 的 Dio 解析路径已被 Task 2 单测覆盖）

- [ ] **Step 4: 全量回归**

Run: `cd health_xiaohe && flutter test`；`cd backend && python -m pytest tests/ -q`
Expected: Flutter 全量 PASS；后端 24 passed（确认没顺手碰坏后端）

- [ ] **Step 5: 验收问题记录**

如有 UI 细节问题（间距/颜色/折叠动画），修复后补充 commit：`fix(flutter/web): Agent 步骤卡片验收修复`

---

## Self-Review 记录

- **Spec 覆盖**：§2 决策（默认全开=Task 3/6；步骤卡片=Task 5/7；仅实时=steps 只在内存模型）✓；§3 协议+type-before-content（Task 2/6）✓；§4 模型与映射规则（Task 1/4/6/7）✓；§5 UI 规范（Task 5/7，token/scoped）✓；§6 文件清单全部对应 ✓；§7 错误边界（Task 4 error 分支、Task 7 onAgentStatus error、流中断走两端现有 onError 路径不需改）✓；§8 测试验收（Task 1-4 单测、Task 6/7 vue-tsc、Task 8 三条 e2e）✓
- **占位符扫描**：无 TBD/TODO/"适当处理" ✓
- **类型一致性**：`AgentStep.asDone`（Task 1 定义，Task 4 消费）✓；`SseChunk.fromEventJson`/`agentStatus`（Task 2 定义，Task 4 消费）✓；`agentSteps`（Task 3 定义，Task 4/5 消费）✓；`thinkingText` 参数（Task 5 内自洽）✓；Vue `AgentStatusEvent`/`AgentStep`/`AGENT_TOOL_LABELS`（Task 6 定义，Task 7 消费）✓
