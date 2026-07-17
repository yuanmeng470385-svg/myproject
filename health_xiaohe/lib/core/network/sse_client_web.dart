// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:health_xiaohe/data/models/sse_chunk.dart';

/// Web 平台 SSE 流式 — XHR + 定时器轮询 responseText。
///
/// 某些浏览器对 text/event-stream 不触发 LOADING 状态，
/// 因此用定时器每 100ms 读取 responseText 增量实现流式效果。
Stream<SseChunk> fetchSseStream({
  required String path,
  required Map<String, dynamic> body,
}) async* {
  final controller = StreamController<SseChunk>();

  final xhr = html.HttpRequest();
  xhr.open('POST', path);
  xhr.setRequestHeader('Content-Type', 'application/json');
  xhr.setRequestHeader('Accept', 'text/event-stream');

  int lastLength = 0;
  String lineBuffer = '';
  Timer? timer;

  void processIncremental(String text) {
    if (text.length <= lastLength) return;

    final newData = lineBuffer + text.substring(lastLength);
    lastLength = text.length;

    final lines = newData.split('\n');
    lineBuffer = lines.removeLast();

    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      final data = trimmed.substring(6);
      if (data == '[DONE]') {
        timer?.cancel();
        controller.close();
        return;
      }
      try {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          for (final c in SseChunk.fromEventJson(json)) {
            controller.add(c);
          }
        }
      } catch (_) {}
    }
  }

  timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    processIncremental(xhr.responseText ?? '');
  });

  xhr.onReadyStateChange.listen((_) {
    if (xhr.readyState == html.HttpRequest.DONE) {
      // 最后一次读取，确保定时器间隙中的数据不丢失
      processIncremental(xhr.responseText ?? '');
      timer?.cancel();
      // 处理最后残留的行
      final lb = lineBuffer.trim();
      if (lb.startsWith('data: ')) {
        final data = lb.substring(6);
        if (data != '[DONE]') {
          try {
            final json = jsonDecode(data);
            if (json is Map<String, dynamic>) {
              for (final c in SseChunk.fromEventJson(json)) {
                controller.add(c);
              }
            }
          } catch (_) {}
        }
      }
      controller.close();
    }
  });

  xhr.onError.listen((_) {
    timer?.cancel();
    controller.addError(Exception('网络请求失败'));
    controller.close();
  });

  xhr.send(jsonEncode(body));

  yield* controller.stream;
}
