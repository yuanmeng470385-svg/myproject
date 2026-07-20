# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

健康小云是一个AI健康助手应用，包含 Flutter 移动端、Vue 3 Web 端和 Python FastAPI 后端。

> **注意**: `backend/` 是 git submodule（gitlink，mode 160000），独立提交。修改后端代码时需要在 `backend/` 目录内单独 commit/push，再回根仓库提交 submodule 指针更新。
>
> ⚠️ 当前根仓库**没有** `.gitmodules` 文件，所以新克隆者直接 `git submodule update --init` 会失败。需要手工补救：`cd backend && git clone <backend-repo-url> .`（或重新跑一次 `git submodule add <url> backend`）。

## 技术栈

### Flutter App (health_xiaohe/)
- **状态管理**: flutter_bloc (BLoC pattern)
- **网络**: dio (HTTP), web_socket_channel (WebSocket)
- **依赖注入**: get_it
- **路由**: go_router
- **本地存储**: shared_preferences
- **Markdown渲染**: flutter_markdown
- **摄像头**: camera (Android), 浏览器 getUserMedia (Web)
- **文件系统**: path_provider

### Python Backend (backend/)
- **框架**: FastAPI + uvicorn
- **数据库**: PostgreSQL + SQLAlchemy (测试用SQLite)
- **认证**: JWT (python-jose + bcrypt)
- **AI模型**: 阿里云百炼 qwen3-omni-flash (文本), qwen3.5-omni-plus-realtime (语音实时通话)
- **实时通信**: websockets (语音通话桥接)

## 目录结构

```
app/
├── health_xiaohe/          # Flutter应用
│   └── lib/
│       ├── core/           # 基础设施: constants, network, storage, theme, audio, camera
│       ├── data/           # 数据层: models, repositories impl
│       ├── domain/         # 领域层: repositories接口(抽象)
│       ├── presentation/   # 表现层: blocs, pages, widgets, router
│       ├── app.dart        # 应用入口 widget (MultiBlocProvider)
│       ├── injection.dart  # 依赖注入配置 (get_it)
│       └── main.dart       # main函数
├── backend/               # Python后端 (git submodule)
│   ├── models/            # SQLAlchemy模型 (User, HealthRecord, Conversation, Message, UserProfile, Memory)
│   ├── routers/           # API路由 (auth, health, consult, voice, user_profile)
│   ├── schemas/           # Pydantic schemas
│   ├── services/          # 业务逻辑 (auth_service, health_service, ai_service, memory_service)
│   ├── utils/             # 工具函数 (security, deps)
│   ├── tests/             # pytest测试 (SQLite隔离)
│   ├── main.py            # FastAPI入口
│   ├── database.py        # 数据库配置 (SessionLocal, engine, Base)
│   └── config.py          # pydantic-settings, 从.env读取
├── start_dev.ps1          # Flutter Web 一键启动 (PowerShell, 后端 + Flutter Chrome)
├── start_web.bat          # xiaohe-web 一键启动 (cmd, 后端 :8002 + Vite :5180)
├── xiaohe-web/            # Vue 3 Web 前端

└── docs/                  # 项目文档
    ├── README.md           # 快速上手和常用命令
    ├── 架构说明.md         # Clean Architecture 分层详解
    ├── 数据流图.md         # 端到端数据流（前端 ↔ 后端 ↔ DashScope）
    ├── 语音通话实现.md     # DashScope Realtime 集成细节
    ├── 部署打包.md         # 构建、部署、测试
    ├── 技术报告.md         # 课程答辩技术报告
    ├── PPT讲稿.md          # PPT 讲稿源文件
    ├── design/             # 设计规范和原型
    └── superpowers/        # AI 辅助开发规划文档
```

## 常用命令

### 一键启动（开发环境）
```powershell
# 同时启动后端 + Flutter Web (Chrome)
.\start_dev.ps1

# 仅后端 / 仅前端
.\start_dev.ps1 -Backend
.\start_dev.ps1 -Frontend

# 启动前先装依赖
.\start_dev.ps1 -Build
```
脚本依赖 `backend/.env`；后端跑在 `:8002`，端口冲突会自动跳过启动。后台 Job 名: `health-xiaohe-backend` / `health-xiaohe-flutter`，停止用 `Get-Job | Stop-Job; Get-Job | Remove-Job`。

### Flutter
```bash
cd health_xiaohe

# 运行 (Web平台)
flutter run -d chrome

# 构建Web
flutter build web

# 运行测试
flutter test

# 运行单测试文件
flutter test test/widget_test.dart
```

### Backend
```bash
cd backend

# 安装依赖
pip install -r requirements.txt

# 开发环境启动
uvicorn main:app --reload --host 0.0.0.0 --port 8002

# 生产环境启动
uvicorn main:app --host 0.0.0.0 --port 8002 --workers 4

# 运行测试 (自动使用SQLite隔离环境)
pytest tests/ -v

# 运行单测试文件
pytest tests/test_auth.py -v
```

## 环境配置

Backend通过 `backend/.env` 文件配置，由 `config.py` 的 `pydantic-settings` 读取。需要配置的环境变量：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DATABASE_URL` | PostgreSQL连接字符串 | `postgresql://user:password@localhost:5432/health_app` |
| `SECRET_KEY` | JWT签名密钥 | 生产环境必须更改 |
| `DASHSCOPE_API_KEY` | 阿里云百炼API密钥 | `sk-xxxxxxxxxxxx` |
| `AI_MODEL` | 文本对话模型 | `qwen3-omni-flash` |

测试自动使用SQLite (`sqlite:///./test_isolated.db`)，无需额外配置。`conftest.py` 在导入前设置 `DATABASE_URL` 环境变量并覆盖数据库引擎。

## API端点

### 认证 (prefix: /api/auth)
- `POST /api/auth/register` - 用户注册 (phone + password)
- `POST /api/auth/login` - 用户登录，返回JWT token
- `GET /api/auth/me` - 获取当前用户信息

### 健康记录 (prefix: /api/health)
- `POST /api/health/records` - 创建健康记录
- `GET /api/health/records` - 获取记录列表 (支持record_type, limit, offset)
- `GET /api/health/records/latest` - 获取各类型最新记录
- `DELETE /api/health/records/{id}` - 删除记录

### AI咨询 (prefix: /api/consult)
- `POST /api/consult/chat` - AI对话 (非流式)
- `POST /api/consult/chat/stream` - AI对话 (SSE流式)
- `GET /api/consult/chat/history` - 获取对话历史 (已废弃，用conversations替代)
- `GET /api/consult/conversations` - 获取对话列表
- `GET /api/consult/conversations/{id}` - 获取对话详情(含消息列表)

### 语音通话 (prefix: /api/consult/voice)
- `POST /api/consult/voice/chat` - 单轮语音对话 (base64音频 → 文本回复)
- `POST /api/consult/voice/chat/stream` - 语音对话流式
- `WS /api/consult/voice/ws` - 实时语音通话WebSocket (需token参数认证)

### 用户画像 & 长期记忆 (prefix: /api/user)
- `GET /api/user/profile` - 获取 UserProfile（性别/年龄/身高/体重/health_summary/risk_tags）+ Top 20 长期记忆
- `PUT /api/user/profile` - 更新画像基本信息
- `DELETE /api/user/memories/{memory_id}` - 删除单条长期记忆

## 架构说明

### Flutter Clean Architecture
- **core/**: 基础设施 — 常量(app_colors, app_spacing, app_strings)、网络客户端(api_client, websocket_client, sse_client)、本地存储、主题、音频录制/播放、摄像头采集
- **core/audio/**: 平台条件导入 — `*_stub.dart`(接口存根) / `*_web.dart`(浏览器) / `*_android.dart`(Android原生)
- **core/camera/**: 同上模式 — `camera_capture_base.dart`(抽象接口) + 平台实现
- **data/**: 数据模型(models)和仓库实现(repositories impl)
- **domain/**: 仓库接口定义(抽象)
- **presentation/**: BLoC状态管理 + UI页面 + 路由 + widgets

### BLoC 模块

| BLoC | 职责 |
|------|------|
| AuthBloc | 登录/注册/认证状态检查 |
| ChatBloc | AI对话，SSE流式接收 |
| ChatHistoryBloc | 对话列表加载和管理 |
| HealthBloc | 健康记录CRUD |
| VoiceBloc | 语音/视频通话状态、WebSocket连接管理、打断处理 |

每个BLoC模块包含 `*_bloc.dart` (逻辑)、`*_event.dart` (事件)、`*_state.dart` (状态)。

**VoiceBloc 关键状态流转**:
`VoiceInitial` → `VoiceConnecting` → `VoiceConnected`(就绪) → `VoiceListening`(用户说话) → `VoiceProcessingInput`(AI处理) → `VoiceReceivingText`/`VoiceReceivingAudio`(AI回复) → `VoiceDone` → `VoiceConnected`(循环)

**VoiceBloc 关键事件**: `VoiceConnect`, `VoiceDisconnect`, `VoiceSendAudioChunk`, `VoiceSendImageChunk`, `VoiceReceiveMessage`, `VoiceError`

### 流式输出架构 (SSE)

AI对话流式输出通过Flutter端的 `sse_client_web.dart` (web平台EventSource) 和 `sse_client_stub.dart` (非web平台存根) 实现。后端 `/api/consult/chat/stream` 使用FastAPI `StreamingResponse` 以SSE格式推送 `data: {json}\n\n` 块，最后发送 `data: [DONE]\n\n`。

### 语音通话架构

```
Flutter → WebSocket → /consult/voice/ws?token=xxx
       ↕ JSON消息 (type: audio / image / commit / ping / stop)
FastAPI voice.py → WebSocket桥接 → DashScope Realtime API (qwen3.5-omni-plus-realtime)
       ↕
DashScope → session.update → response.audio.delta / response.audio_transcript.delta / response.done
```

Flutter端 `VoiceBloc` 通过 `WebSocketClient` 管理连接。`AudioRecorder`/`AudioPlayer`/`CameraCapture` 均通过 Dart 条件导入实现平台适配:
- Web: `audio_recorder_web.dart` (AudioContext+PCM编码), `camera_capture_web.dart` (getUserMedia+Canvas JPEG)
- Android: `audio_recorder_android.dart`, `camera_capture_android.dart` (camera插件)
- Stub: 非支持平台的空实现

WebSocket消息类型:
- **Flutter→Backend**: `audio` (base64 PCM), `image` (base64 JPEG), `commit` (提交音频缓冲区), `ping` (15s心跳), `stop`
- **Backend→Flutter**: `connected` (含conversation_id), `text` (AI文本流), `audio` (AI音频delta), `speech_started` (用户打断), `speech_stopped` (用户说完), `user_text` (用户转录), `ai_text` (AI完整回复), `done`, `error`

**噪声门**: `AudioRecorderBase.gateOn()` 压低麦克风过滤环境噪音，`gateOff()` 恢复全量收音。AI说话时开启噪声门防止回声，用户说话时关闭。

**打断机制**: DashScope检测到用户语音 (`input_audio_buffer.speech_started`) → 后端发送 `response.cancel` 取消AI回复 → 通知Flutter `speech_started` → VoiceBloc进入 `VoiceListening` 状态 → 用户说完后 `speech_stopped` → 清除打断标志，处理新输入。

**视频通话**: 摄像头采集JPEG帧，通过 `VoiceSendImageChunk` 事件经WebSocket发送 `image` 类型消息到后端，后端转为 DashScope `input_image_buffer.append` 协议。DashScope要求先有音频数据才能接收图像。

**语音转录持久化**: `voice.py` 的 `_save_voice_message()` 在收到 `response.audio_transcript.done` (AI) 和 `conversation.item.input_audio_transcription.completed` (用户) 时自动保存转录文本到 Message 表。

### 对话持久化

`consult.py` 的 `_save_chat_messages()` 在每次AI回复后自动持久化。支持两种模式:
- **新对话**: 不传 `conversation_id`，自动创建Conversation
- **继续对话**: 传 `conversation_id`，追加新消息到已有对话

流式接口在生成完所有内容后，通过SSE返回 `conversation_id` 供前端后续使用。

### 用户画像 & 长期记忆

`models/memory.py` 定义两张表：
- **UserProfile**: 1:1 关联 User，存基础人口学字段 + AI 生成的 `health_summary` + `risk_tags` 数组
- **Memory**: 用户级长期记忆条目，含 `category`(habit/disease/preference 等) + `fact`(自然语言) + `importance`(权重) + 去重逻辑

AI 对话/语音通话产生的事实经过去重后写入 Memory，对话上下文构建时会把高 importance 条目和 HealthRecord 一并注入 system prompt（即"健康记录上下文"机制）。

## 路由与导航

Flutter使用 `go_router` 和 `ShellRoute` 实现底部导航栏:

```
/ (启动页) → /login (登录) → /chat (聊天首页, 支持 ?conversationId=xxx 继续历史对话)
                             ├── /ai-impression (AI 画像 + 长期记忆，原 /health-records)
                             ├── /chat-history (对话历史列表)
                             ├── /profile (个人中心)
                             ├── /call (语音通话，全屏页面，不在 ShellRoute 内)
                             ├── /settings (设置页，全屏页面)
                             └── /chat-history/:conversationId (对话详情)
```

底部导航栏4个tab: **咨询、画像、历史、我的**。`/ai-impression` 由 `user_profile_page.dart` 渲染，调用 `/api/user/profile` 展示用户画像和长期记忆。`/call` 和 `/settings` 是独立全屏路由（不使用底部导航栏）。

> 历史命名: 路由常量是 `AppRouter.aiImpression` (commit `7f2de59` 重命名)。旧代码/文档里的 `/health-records` 已废弃。

## 设计规范

> **当前视觉系统(`feat/visual-redesign` 分支)**: 「奶油暖调 · 哑光鼠尾草」token 化体系，已取代旧的 `#4ECDC4` 蓝绿色板。所有颜色/字体/动效/圆角/阴影都集中在 `core/constants/` 的 token 类里，**新增 UI 一律引用 token，不要再写裸 hex**。设计参考 `docs/design/2026-04-30-健康小荷-Flutter-App设计规范.md` 与 `健康小荷App原型.html`(注意设计文档命名用「小荷」，代码/产品名是「小云」)。

### 设计 token(`core/constants/`)

| token 类 | 文件 | 关键值 |
|----------|------|--------|
| `AppColors` | `app_colors.dart` | 主色鼠尾草 `#7FB3A8`、燕麦奶油背景 `#F6F4EE`、暖砂点缀 `#B9A88F`、暖墨文字阶。**旧名(primary/aiBubbleBg/textPrimary…)保留为别名重映射到新色板**，未改造页面自动呈现新配色 |
| `AppTypography` | `app_typography.dart` | 宋体大标题 `NotoSerifSC`(displaySerif/headingSerif) + `Fraunces` 英数/数字 + 系统正文。⚠️ **字体文件尚未在 `pubspec.yaml` 声明(commit `1b25ce9` 标注"字体待后补")**，目前会回退到系统字体 |
| `AppMotion` | `app_motion.dart` | 静润曲线 `calm = Cubic(0.22,0.61,0.36,1)`(强缓出、无回弹)、fast/base/slow(180/280/420ms)、stagger 步进 60ms(最多 5 档) |
| `AppRadius` | `app_radius.dart` | chip 16 / bubble 18(尾角 6) / card 20 / input 24 |
| `AppShadows` | `app_shadows.dart` | 暖投影(基于砂/墨色低透明,非纯黑): soft / card / primary |

主题在 `core/theme/app_theme.dart` 的 `AppTheme.lightTheme` 统一装配(Material3 `ColorScheme.fromSeed` + 各组件 theme 套 token)。

### 动效基础设施(`core/animations/`)

- `entrance.dart` — `Entrance(index: i, child: ...)` 包裹首屏元素做"淡入 + 上浮"入场，`index` 控制 stagger 错峰；仅首次构建跑一次。
- `page_transitions.dart` — `fadeUpPage()` 统一页面过渡(淡入 + 轻上浮，静润曲线)，`app_router.dart` 所有顶层 `GoRoute` 的 `pageBuilder` 都用它；ShellRoute 内 tab 切换用 `AnimatedSwitcher`(`AppMotion.fast`)。
- 底部导航是自定义 `widgets/common/app_bottom_nav.dart`(非 Material `BottomNavigationBar`)。

### API 端口

Flutter 端 `core/network/api_endpoints.dart` 通过 `--dart-define` 注入环境变量，支持不同环境切换：

```bash
# 默认走远程服务器（无需 --dart-define）
flutter run -d chrome

# 连本地后端
flutter run --dart-define=API_HOST=localhost -d chrome

# 连局域网 IP（手机/模拟器真机联调）
flutter run --dart-define=API_HOST=192.168.x.y -d chrome

# 改端口 / HTTPS
flutter run --dart-define=API_HOST=localhost --dart-define=API_PORT=8003
flutter run --dart-define=API_HOST=myserver.com --dart-define=API_SCHEME=https
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `API_HOST` | `118.31.166.235` | 后端服务器地址 |
| `API_PORT` | `8002` | 后端端口 |
| `API_SCHEME` | `http` | 协议 |

> **Android 明文 HTTP 联调**: Android 默认禁止明文 HTTP，连不上 `:8002` 开发后端。`AndroidManifest.xml` 已开 `usesCleartextTraffic="true"` + `networkSecurityConfig="@xml/network_security_config"`，白名单仅放行 `localhost`、`10.0.2.2`(标准 AVD 宿主机)、`192.168.1.84` 网段；换局域网 IP 联调时需同步改 `res/xml/network_security_config.xml`。release 接 HTTPS 时 `base-config` 不放行公网明文。Android 权限 (`INTERNET`/`RECORD_AUDIO`/`CAMERA`) 也在该 manifest 声明。

除了 Flutter 端 `health_xiaohe/`，根目录另有一个 web 前端 `xiaohe-web/` —— 温柔生物形态美学的 SPA，Vite + Vue 3 + TS + Pinia + vue-router。直接对接 `:8002` 后端（vite 开发期 proxy `/api` → `localhost:8002`）。

```bash
cd xiaohe-web
npm install
npm run dev        # http://localhost:5180
```

更便捷的入口：根目录的 `start_web.bat` 会同时检查环境、起后端（uvicorn :8002 --reload，等 `/health` 200 后）、起 Vite（:5180，自动打开 Chrome），并把两边日志拆到独立 cmd 窗口。停止服务直接关那两个弹窗即可。

页面：`/`(landing) · `/login` · `/chat`(流式 + markdown) · `/call`(语音通话) · `/history` · `/profile` · `/records`。流式聊天用 fetch + ReadableStream（不能用 EventSource — 后端 `POST /api/consult/chat/stream` 需要 `Authorization` header），前端有打字机节流（默认 60 字/秒）。AI 回复经 `marked` + `dompurify` 渲染 markdown。

语音/视频通话模块（`src/lib/`）：

| 模块 | 文件 | 职责 |
|------|------|------|
| voice-session | `voice-session.ts` | WebSocket 连接管理，对标 Flutter VoiceBloc |
| audio/recorder | `audio/recorder.ts` | 浏览器麦克风采集 (AudioContext + ScriptProcessor, 16kHz PCM) |
| audio/player | `audio/player.ts` | PCM→WAV 播放 |
| video/camera | `video/camera.ts` | getUserMedia 摄像头采集，Canvas 定时截图 JPEG 帧上行 |

> `voice-session.ts` 维护 WebSocket 生命周期和回调（onText/onAudio/onUserText/onAiText/onDone/onError），与后端 `/api/consult/voice/ws` 协议一致。通话页面 `CallPage.vue` 使用这些模块实现完整的语音+视频通话 UI。

### web 端踩过的坑（修过的真 bug，值得防范）

1. **Vue 3 reactive plain-object + closure 引用导致响应式静默失效**：
   ```ts
   const aiMsg = { content: "" };       // plain
   messages.value.push(aiMsg);          // Vue 内部建 proxy，但闭包仍指向原始对象
   onChunk(d => { aiMsg.content += d }) // 改原始对象 → 不触发 setter → DOM 不更新
   ```
   症状：流式逐字看不到，最后一次性"突然全部出现"（其实是别的 ref 改动触发了 re-render，render 时通过 proxy 读到了被悄悄改完的最新值）。修法：`const aiMsg = reactive({...})` 显式包装后再 push，闭包持有的就是 proxy 本身。**任何"raf loop 写属性"或"流式逐字更新"的场景必须这样做。** 见 `xiaohe-web/src/pages/ChatPage.vue` 的 send()。

2. **Pinia setup store 的 computed 短路求值导致依赖追踪丢失**：
   ```ts
   const isAuthed = computed(() => !!getToken() && !!user.value);
   ```
   初始 token 是 null，`&&` 短路，`user.value` 没被读到 → computed 的 deps 里**没有 user** → 之后 user.value 被赋值也不触发重算，isAuthed 永远是初始的 false。修法：把 reactive ref 放 `&&` 左边（`user.value !== null && !!getToken()`）或独立访问一次。见 `xiaohe-web/src/stores/auth.ts`。

3. **Google Fonts API v2 variable axes 必须按"大写在前 / 小写在后，组内字母序"排**：
   `Fraunces:SOFT,ital,opsz,wght@...` 对，`Fraunces:ital,opsz,wght,SOFT@...` 返回 200 但 variable 轴失效，浏览器静默回退到 fallback 字体。见 `xiaohe-web/index.html`。

4. **Vue scoped style 不会作用于 v-html 注入的子元素**：用 `:deep()` 或把样式放 `global.css`。markdown 渲染的 `<strong>` `<ol>` 等样式都在 `xiaohe-web/src/styles/global.css` 的 `.md` 命名空间下。

### 给 web 端 chat 流式后端的协议契约

- 后端 SSE 帧格式：`data: {json}\n\n`，三种 json payload：
  - `{ content: "delta" }` — chunk
  - `{ conversation_id: "..." }` — 持久化后告诉前端，用于后续续聊
  - `{ suggestions: [...] }` — 跟问建议
- 终止符：`data: [DONE]\n\n`
- 必须在 response header 设 `X-Accel-Buffering: no` 否则某些反代会缓冲整段才发

## 第二前端: xiaohe-web (Vite + Vue 3)
