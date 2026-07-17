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
