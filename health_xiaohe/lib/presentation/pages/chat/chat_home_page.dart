// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:health_xiaohe/core/constants/app_colors.dart';
import 'package:health_xiaohe/core/constants/app_radius.dart';
import 'package:health_xiaohe/core/constants/app_strings.dart';
import 'package:health_xiaohe/core/constants/app_typography.dart';
import 'package:health_xiaohe/core/animations/entrance.dart';
import 'package:health_xiaohe/presentation/blocs/auth/auth_bloc.dart';
import 'package:health_xiaohe/presentation/blocs/auth/auth_state.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_bloc.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_event.dart';
import 'package:health_xiaohe/presentation/blocs/chat/chat_state.dart';
import 'package:health_xiaohe/presentation/router/app_router.dart';
import 'package:health_xiaohe/presentation/widgets/chat/chat_input_field.dart';
import 'package:health_xiaohe/presentation/widgets/chat/message_bubble.dart';

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final _scrollController = ScrollController();

  // 已完成的 AI 气泡按消息对象身份缓存对应 widget 实例。
  // 流式期间整列每 ~50ms 重建一次，靠 identical(old,new) 短路让历史气泡跳过
  // rebuild —— 否则可见的旧气泡会反复重新解析 Markdown。Expando 随对象 GC，无需手动清理。
  final _bubbleCache = Expando<Widget>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
  }

  void _initChat() {
    if (!mounted) return;
    final routerState = GoRouterState.of(context);
    final convId = routerState.uri.queryParameters['conversationId'];
    if (convId != null && convId.isNotEmpty) {
      context.read<ChatBloc>().add(ChatLoadConversation(convId));
    } else {
      context.read<ChatBloc>().add(ChatInitialize());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildSideDrawer(context),
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Row(
            children: [
              Builder(
                builder: (context) => GestureDetector(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.logo),
                    ),
                    child: const Center(
                      child: Text('🌿', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.chatHomeTitle,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state.conversationId != null) {
                return IconButton(
                  icon: Icon(LucideIcons.plus, color: AppColors.primary),
                  tooltip: '新建对话',
                  onPressed: () {
                    context.read<ChatBloc>().add(ChatNewConversation());
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              // 只在消息条数变化、错误出现、或流式状态翻转时触发 listener；
              // 流式中字数增长不再每个 chunk 都触发 animateTo
              listenWhen: (prev, cur) =>
                  prev.messages.length != cur.messages.length ||
                  prev.error != cur.error ||
                  prev.isStreaming != cur.isStreaming,
              // 仅当消息列表/流式/加载态变化才重建列表；suggestions、conversationId
              // 等变化不再触发整列重建（copyWith 未改 messages 时引用不变）
              buildWhen: (prev, cur) =>
                  !identical(prev.messages, cur.messages) ||
                  prev.isStreaming != cur.isStreaming ||
                  prev.isLoading != cur.isLoading ||
                  prev.agentThinking != cur.agentThinking,
              listener: (context, state) {
                if (state.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.error!),
                      backgroundColor: AppColors.danger,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
                if (state.messages.isNotEmpty) {
                  _scrollToBottom();
                }
              },
              builder: (context, state) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length + 1, // +1 for welcome card
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildWelcomeCard();
                    }
                    final msgIndex = index - 1;
                    final msg = state.messages[msgIndex];
                    final isLast = msgIndex == state.messages.length - 1;
                    final streaming =
                        isLast && state.isStreaming && msg.isAssistant;

                    // 已完成的 AI 气泡：复用缓存的 widget 实例，rebuild 时被短路跳过
                    if (msg.isAssistant && !streaming) {
                      return _bubbleCache[msg] ??= RepaintBoundary(
                        child: MessageBubble(message: msg, isStreaming: false),
                      );
                    }
                    // 流式气泡 / 用户气泡：RepaintBoundary 把光标闪烁等重绘和列表其余部分隔离
                    return RepaintBoundary(
                      child: MessageBubble(
                        message: msg,
                        isStreaming: streaming,
                        thinkingText: streaming ? state.agentThinking : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // 追问建议
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state.suggestions.isNotEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8, runSpacing: 8,
                    children: state.suggestions.map((s) => GestureDetector(
                      onTap: () {
                        context.read<ChatBloc>().add(ChatSendMessage(s));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.bgSubtle,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(s,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.primaryDark)),
                      ),
                    )).toList(),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Loading indicator
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state.isLoading) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        AppStrings.thinking,
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Input field
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, authState) {
              return ChatInputField(
                onSendMessage: (message) {
                  context.read<ChatBloc>().add(ChatSendMessage(message));
                },
                onSendImage: (bytes) {
                  context.read<ChatBloc>().add(ChatSendMessage('', imageBytes: bytes));
                },
                onVoicePressed: () {
                  if (authState is AuthAuthenticated) {
                    _startVoiceCall();
                  }
                },
                onHealthRecordPressed: () {
                  context.push(AppRouter.aiImpression);
                },
                onCallPressed: () {
                  if (authState is AuthAuthenticated) {
                    _startVoiceCall();
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _startVoiceCall() {
    final state = context.read<ChatBloc>().state;
    final convId = state.conversationId;
    if (convId != null) {
      context.go('/call?conversationId=$convId');
    } else {
      context.go(AppRouter.call);
    }
  }

  Widget _buildSideDrawer(BuildContext context) {
    return Drawer(
      width: 280,
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          final userName = authState is AuthAuthenticated ? authState.user.nickname : '用户';
          final userPhone = authState is AuthAuthenticated ? authState.user.phone : '';

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 30,
                  left: 24,
                  right: 24,
                  bottom: 24,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🌿', style: TextStyle(fontSize: 32)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (userPhone.isNotEmpty)
                      Text(
                        userPhone.replaceRange(3, 7, '****'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    _buildDrawerItem(
                      context,
                      icon: Icons.chat_bubble_outline,
                      title: 'AI 健康咨询',
                      onTap: () {
                        Navigator.pop(context);
                        context.go(AppRouter.chatHome);
                      },
                    ),
                    _buildDrawerItem(
                      context,
                      icon: Icons.psychology_outlined,
                      title: 'AI 印象',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(AppRouter.aiImpression);
                      },
                    ),
                    _buildDrawerItem(
                      context,
                      icon: Icons.history,
                      title: '咨询历史',
                      color: AppColors.primaryDark,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(AppRouter.chatHistory);
                      },
                    ),
                    _buildDrawerItem(
                      context,
                      icon: Icons.person_outline,
                      title: '个人中心',
                      color: AppColors.textTertiary,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(AppRouter.personalCenter);
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.primary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }

  String _greetingByHour() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了,我是小云';
    if (h < 11) return '早安,我是小云';
    if (h < 14) return '午安,我是小云';
    if (h < 18) return '下午好,我是小云';
    return '晚上好,我是小云';
  }

  Widget _buildWelcomeCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Entrance(
            index: 0,
            child: Text('HEALTH XIAOHE', style: AppTypography.overline),
          ),
          const SizedBox(height: 6),
          Entrance(
            index: 1,
            child: Text(_greetingByHour(), style: AppTypography.displaySerif),
          ),
          const SizedBox(height: 4),
          Entrance(
            index: 2,
            child: Text(
              '今天想聊些什么?我都在。',
              style: TextStyle(
                fontFamily: null,
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (prev, cur) =>
                prev.welcomeSuggestions != cur.welcomeSuggestions,
            builder: (context, state) {
              final tips = state.welcomeSuggestions.isNotEmpty
                  ? state.welcomeSuggestions
                  : const ['失眠怎么办', '血压正常值', '春季养生'];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < tips.length; i++)
                    Entrance(index: 3 + i, child: _buildQuickTip(tips[i])),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTip(String text) {
    return GestureDetector(
      onTap: () {
        context.read<ChatBloc>().add(ChatSendMessage(text));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          text,
          style: AppTypography.caption.copyWith(color: AppColors.primaryDark),
        ),
      ),
    );
  }
}
