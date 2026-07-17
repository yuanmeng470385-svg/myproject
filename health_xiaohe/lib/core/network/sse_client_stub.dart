// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:health_xiaohe/core/network/api_client.dart';
import 'package:health_xiaohe/data/models/sse_chunk.dart';

/// 非 Web 平台 SSE 流式 — 使用 Dio ResponseType.stream
Stream<SseChunk> fetchSseStream({
  required String path,
  required Map<String, dynamic> body,
}) async* {
  final dio = GetIt.instance<ApiClient>().dio;
  final controller = StreamController<SseChunk>();

  try {
    final response = await dio.post(
      path,
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    response.data.stream.listen(
      (chunk) {
        final lines = utf8.decode(chunk, allowMalformed: true).split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
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
      },
      onError: (error) {
        controller.addError(error);
        controller.close();
      },
      onDone: () {
        controller.close();
      },
    );
  } on DioException catch (e) {
    controller.addError(
      Exception(e.response?.data?['detail'] ?? '发送消息失败'),
    );
    controller.close();
  }

  yield* controller.stream;
}
