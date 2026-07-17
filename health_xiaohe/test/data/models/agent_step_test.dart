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
