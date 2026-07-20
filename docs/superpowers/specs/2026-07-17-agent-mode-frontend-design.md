# Agent 模式前端接入设计（Flutter Android + xiaohe-web）

- 日期：2026-07-17
- 状态：已评审通过（待实施）
- 范围：`health_xiaohe/`（Flutter，Android + Web 平台）、`xiaohe-web/`（Vue 3）
- 不在范围：语音通话页（WebSocket Realtime，与 Agent 无关）、历史对话步骤回溯

## 1. 背景与目标

后端 Agent 体系已完成并验证（ReAct 循环 + 6 工具 + 执行日志落库）：`POST /api/consult/chat/stream` 请求体带 `agent_mode: true` 时，SSE 流中会混入 `agent_status` 事件（thinking / tool_call / tool_result / error）。当前两个前端不发送该参数、也不认识这些事件，Agent 能力用户完全用不到。

目标：两端聊天页默认启用 Agent 模式，把工具调用过程可视化为消息气泡内的可折叠步骤卡片。

## 2. 已确认的产品决策

| 决策点 | 结论 |
|--------|------|
| 触发方式 | 默认全开，所有消息都带 `agent_mode: true`，无 UI 开关；是否调工具由 AI 自行决定 |
| 过程展示 | 步骤卡片：进行中逐条显示 + 动效，完成后折叠为摘要行，可展开看工具原始返回 |
| 历史回溯 | 仅实时（会话内存里保留）；重开历史对话只显示最终回答，不加后端查询 API |

## 3. 协议契约（后端已实现，前端只消费）

端点不变：`POST /api/consult/chat/stream`（保留追问建议、标题生成、对话持久化）。`/api/agent/chat/stream` 前端不使用。

SSE 帧格式 `data: {json}\n\n`，在原有 payload（`{content}` / `{conversation_id}` / `{suggestions}` / `[DONE]`）之外新增：

```json
{"type":"agent_status","status":"thinking","content":"正在分析您的问题..."}
{"type":"agent_status","status":"tool_call","tool":"query_health_records","args":{"record_type":"blood_pressure","days":7}}
{"type":"agent_status","status":"tool_result","tool":"query_health_records","result":"血压记录（最近 7 天）：..."}
{"type":"agent_status","status":"error","content":"处理出错: ..."}
```

注意：`thinking` 事件也有 `content` 字段。解析时必须**先判 `type` 再判 `content`**，否则思考文案会被拼进回答气泡（这是接入的硬性正确性要求，不只是 UI 增强）。

## 4. 数据模型（两端同构）

```
AgentStep {
  tool:   String                 // 工具名（原始）
  args:   Map / object | null    // 调用参数
  result: String | null          // 工具返回文本（后端已截断 500 字符）
  status: 'running' | 'done'
}
```

事件 → 状态映射规则：

| 事件 | 处理 |
|------|------|
| `thinking` | 不建步骤；更新气泡占位文字为事件的 content（替代现有"正在听你说的话…"/加载态） |
| `tool_call` | 追加一个 `status=running` 的 AgentStep |
| `tool_result` | 找**最后一个同名且 running** 的步骤 → 置 `done`、填 result；找不到则忽略 |
| `error` | 所有 running 步骤置 done；错误文案走两端现有错误渲染路径 |
| `{content}` 等原有 payload | 原逻辑不动 |

步骤列表挂在**消息对象**上（Flutter `ChatMessageModel.agentSteps`、Vue `UIMsg.steps`），本次会话内滚动可见；`toApiFormat()` / 发给后端的 messages 不包含该字段。

工具中文标签映射（两端各一份常量，未知工具名回退显示原名）：

| 工具名 | 标签 |
|--------|------|
| query_health_records | 查询健康记录 |
| get_latest_health_records | 获取最新记录 |
| analyze_health_trend | 趋势分析 |
| get_user_profile_summary | 读取健康画像 |
| calculator | 计算 |
| get_current_datetime | 获取时间 |

## 5. UI 规范

位置：AI 气泡内部、回答文字上方。

- **进行中**：每步一行 = 工具图标 + 中文标签 + 转圈指示；收到 tool_result 后该行变 ✓
- **完成后**：整块折叠为一行摘要"⚙ 已调用 N 个工具 ▾"；点击展开步骤列表；点击单个步骤展开工具原始返回（小号等宽字体）
- **无工具调用的回答**：不渲染步骤卡片，与现在完全一致
- Flutter：颜色/圆角/动效全部引用 token（`AppColors` / `AppRadius` / `AppMotion`），禁止裸 hex（visual-redesign 分支规范）；新组件独立文件 `agent_steps_card.dart`
- Vue：样式写在组件 scoped 内，注意 `v-html` 内容样式需 `:deep()` 或走 `global.css`

## 6. 改动文件清单

### Flutter（health_xiaohe/lib/）

| 文件 | 改动 |
|------|------|
| `data/models/agent_step.dart` | 新建：AgentStep 模型（tool/args/result/status + 中文标签映射常量） |
| `data/models/sse_chunk.dart` | + `agentStatus` 字段（原始 event map）+ `hasAgentStatus` |
| `core/network/sse_client_stub.dart` | 解析分支：`type == 'agent_status'` → SseChunk(agentStatus)；**先判 type 再判 content** |
| `core/network/sse_client_web.dart` | 同上（两处解析点同步改） |
| `data/models/chat_message_model.dart` | + `agentSteps: List<AgentStep>?`（copyWith 支持；toApiFormat 不变） |
| `data/repositories/chat_repository_impl.dart` | 请求体 + `'agent_mode': true` |
| `presentation/blocs/chat/chat_bloc.dart` | `_onReceiveChunk` 加 agent_status 分发，按映射规则更新流式中消息的 agentSteps |
| `presentation/widgets/chat/agent_steps_card.dart` | 新建：步骤卡片组件（进行中/折叠两态） |
| `presentation/widgets/chat/message_bubble.dart` | AiMessageBubble 中嵌入 AgentStepsCard |

### Vue（xiaohe-web/src/）

| 文件 | 改动 |
|------|------|
| `services/chat.ts` | 请求体 + `agent_mode: true`；解析分支**最前面**加 `obj.type === 'agent_status'` → `cb.onAgentStatus?.(obj)`；`StreamCallbacks` + `onAgentStatus` |
| `pages/ChatPage.vue` | `UIMsg` + `steps`（**必须 reactive 包裹**，闭包引用坑）；onAgentStatus 实现映射规则；模板加步骤卡片；scoped 样式 |

后端：**零改动**。

## 7. 错误与边界

- `agent_status.error`：running 步骤全部置 done，错误文案进气泡（沿用现有错误路径），不留转圈残骸
- 兼容性：后端若不发 agent_status（普通模式/旧后端），两端表现与现状完全一致
- 同一工具被多次调用：tool_result 只匹配最后一个同名 running 步骤
- 流中断（网络断/用户取消）：running 步骤置 done，沿用两端现有中断处理

## 8. 测试与验收

- Flutter 单测：SseChunk 对 agent_status 的解析；ChatBloc 事件分发（tool_call 建步骤 / tool_result 闭合 / thinking 不建步骤 / content 不受影响）
- Vue：`npm run build` 通过类型检查
- 端到端验收（起真实后端，两端各一次）：
  1. 问"帮我分析最近的血压趋势" → 步骤卡片逐条出现并闭合 → 最终回答含真实数据 → 完成后折叠可展开
  2. 问"你好" → 无步骤卡片，行为与现在一致
  3. 会话内发第二条消息后回滚查看第一条 → 步骤仍可展开
