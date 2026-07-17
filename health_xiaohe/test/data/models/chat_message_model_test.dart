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
