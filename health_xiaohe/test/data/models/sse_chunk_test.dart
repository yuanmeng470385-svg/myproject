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
