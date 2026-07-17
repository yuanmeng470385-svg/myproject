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
