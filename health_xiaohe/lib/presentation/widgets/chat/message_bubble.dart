// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:health_xiaohe/core/constants/app_colors.dart';
import 'package:health_xiaohe/core/constants/app_motion.dart';
import 'package:health_xiaohe/core/constants/app_radius.dart';
import 'package:health_xiaohe/core/constants/app_shadows.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';
import 'package:health_xiaohe/presentation/widgets/chat/agent_steps_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isStreaming;
  final String? thinkingText;

  const MessageBubble({super.key, required this.message, this.isStreaming = false, this.thinkingText});

  @override
  Widget build(BuildContext context) {
    final child = message.isUser
        ? UserMessageBubble(message: message)
        : AiMessageBubble(message: message, isStreaming: isStreaming, thinkingText: thinkingText);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.base,
      curve: AppMotion.calm,
      builder: (context, t, c) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * AppMotion.entranceOffset),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

class AiMessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isStreaming;
  final String? thinkingText;

  const AiMessageBubble({super.key, required this.message, this.isStreaming = false, this.thinkingText});

  static final _styleSheet = MarkdownStyleSheet(
    h1: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      height: 1.4,
    ),
    h2: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      height: 1.4,
    ),
    h3: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      height: 1.4,
    ),
    p: TextStyle(
      fontSize: 16,
      color: AppColors.textSecondary,
      height: 1.5,
    ),
    strong: TextStyle(
      fontWeight: FontWeight.w600,
      color: AppColors.secondary,
    ),
    em: TextStyle(fontStyle: FontStyle.italic),
    code: TextStyle(
      backgroundColor: AppColors.bgSubtle,
      fontSize: 14,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.bgSubtle,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
      border: Border(
        left: BorderSide(color: AppColors.primary, width: 3),
      ),
    ),
    blockquotePadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.divider, width: 1),
      ),
    ),
    listBullet: TextStyle(
      fontSize: 16,
      color: AppColors.textSecondary,
    ),
    tableBody: TextStyle(
      fontSize: 14,
      color: AppColors.textSecondary,
    ),
  );

  // 流式期间的纯文本样式，和 Markdown 的 p 样式保持一致，完成时无缝切到 MarkdownBody
  static TextStyle get _streamingTextStyle => TextStyle(
        fontSize: 16,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🌿', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.bubbleTail),
                  topRight: Radius.circular(AppRadius.bubble),
                  bottomLeft: Radius.circular(AppRadius.bubble),
                  bottomRight: Radius.circular(AppRadius.bubble),
                ),
                border: Border.all(color: AppColors.borderSoft),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    // 流式中用纯 Text：避免每 ~50ms 把不断变长的整段 Markdown
                    // 重新解析一遍 + SelectableText 的额外开销；完成后再渲染富文本
                    isStreaming
                        ? Text(message.content, style: _streamingTextStyle)
                        : MarkdownBody(
                            data: message.content,
                            styleSheet: _styleSheet,
                            selectable: true,
                          ),
                  if (isStreaming)
                    Padding(
                      padding: EdgeInsets.only(top: message.content.isEmpty ? 4 : 2),
                      child: const _BlinkingCursor(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (message.timestamp != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat('HH:mm').format(message.timestamp!),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class UserMessageBubble extends StatelessWidget {
  final ChatMessageModel message;

  const UserMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.timestamp != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat('HH:mm').format(message.timestamp!),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.bubble),
                  topRight: Radius.circular(AppRadius.bubbleTail),
                  bottomLeft: Radius.circular(AppRadius.bubble),
                  bottomRight: Radius.circular(AppRadius.bubble),
                ),
                boxShadow: AppShadows.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (message.hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        message.imageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                  if (message.hasImage && message.content.isNotEmpty)
                    const SizedBox(height: 8),
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: AppColors.userBubbleText,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
