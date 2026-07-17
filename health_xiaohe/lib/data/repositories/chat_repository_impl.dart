// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:health_xiaohe/core/network/api_client.dart';
import 'package:health_xiaohe/core/network/sse_client_stub.dart'
    if (dart.library.html) 'package:health_xiaohe/core/network/sse_client_web.dart';
import 'package:health_xiaohe/core/storage/local_storage.dart';
import 'package:health_xiaohe/data/models/chat_message_model.dart';
import 'package:health_xiaohe/data/models/conversation_model.dart';
import 'package:health_xiaohe/data/models/sse_chunk.dart';
import 'package:health_xiaohe/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ApiClient _apiClient;

  ChatRepositoryImpl(this._apiClient);

  @override
  Stream<SseChunk> getChatStream(List<ChatMessageModel> messages, {String? conversationId}) async* {
    final apiMessages = messages.map((m) => m.toApiFormat()).toList();
    final body = <String, dynamic>{
      'messages': apiMessages,
      'agent_mode': true, // Agent 模式默认全开，是否调工具由 AI 决定
      if (conversationId != null) 'conversation_id': conversationId,
    };

    if (kIsWeb) {
      final localStorage = GetIt.instance<LocalStorage>();
      final tokenValue = localStorage.getJwtToken() ?? '';
      final baseUrl = _apiClient.dio.options.baseUrl;
      final sseUrl =
          '$baseUrl/api/consult/chat/stream?token=${Uri.encodeComponent(tokenValue)}';
      yield* fetchSseStream(path: sseUrl, body: body);
    } else {
      yield* fetchSseStream(path: '/api/consult/chat/stream', body: body);
    }
  }

  @override
  Future<ChatResult<List<ConversationItemModel>>> getConversations() async {
    try {
      final response = await _apiClient.getConversations();
      final list = (response.data['conversations'] as List)
          .map((item) => ConversationItemModel.fromJson(item))
          .toList();
      return ChatResult.success(list);
    } on DioException catch (e) {
      final message = e.response?.data?['detail'] ?? '获取对话列表失败';
      return ChatResult.failure(message.toString());
    } catch (e) {
      return ChatResult.failure('获取对话列表失败: $e');
    }
  }

  @override
  Future<ChatResult<ConversationDetailModel>> getConversationDetail(String id) async {
    try {
      final response = await _apiClient.getConversationDetail(id);
      final detail = ConversationDetailModel.fromJson(response.data);
      return ChatResult.success(detail);
    } on DioException catch (e) {
      final message = e.response?.data?['detail'] ?? '获取对话详情失败';
      return ChatResult.failure(message.toString());
    } catch (e) {
      return ChatResult.failure('获取对话详情失败: $e');
    }
  }

  @override
  Future<ChatResult<ChatMessageModel>> sendMessage(List<ChatMessageModel> messages) async {
    try {
      final apiMessages = messages.map((m) => m.toApiFormat()).toList();
      final response = await _apiClient.chat(apiMessages);

      final content = response.data['choices']?[0]?['message']?['content'] ?? '';
      return ChatResult.success(ChatMessageModel.assistant(content));
    } on DioException catch (e) {
      final message = e.response?.data?['detail'] ?? '发送消息失败';
      return ChatResult.failure(message.toString());
    } catch (e) {
      return ChatResult.failure('发送消息失败: $e');
    }
  }

  @override
  Future<ChatResult<void>> deleteConversation(String id) async {
    try {
      await _apiClient.deleteConversation(id);
      return ChatResult.success(null);
    } on DioException catch (e) {
      final message = e.response?.data?['detail'] ?? '删除失败';
      return ChatResult.failure(message.toString());
    } catch (e) {
      return ChatResult.failure('删除失败: $e');
    }
  }

  @override
  Future<ChatResult<List<String>>> getWelcomeSuggestions() async {
    try {
      final response = await _apiClient.getWelcomeSuggestions();
      final list = (response.data['suggestions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      return ChatResult.success(list);
    } catch (e) {
      return ChatResult.failure(e.toString());
    }
  }
}
