// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
class ApiEndpoints {
  ApiEndpoints._();

  // 通过 --dart-define 注入，无参数时默认走当前 PC 的局域网 IP，方便手机真机直连
  //   PC 本机 dev:  flutter run --dart-define=API_HOST=localhost
  //   换网络换 IP:  flutter run --dart-define=API_HOST=192.168.x.y
  //   改端口:      flutter run --dart-define=API_PORT=8003
  //   走 HTTPS:    flutter run --dart-define=API_SCHEME=https
  static const String _host =
      String.fromEnvironment('API_HOST', defaultValue: '118.31.166.235');
  static const String _port =
      String.fromEnvironment('API_PORT', defaultValue: '8002');
  static const String _scheme =
      String.fromEnvironment('API_SCHEME', defaultValue: 'http');

  static String get baseUrl => '$_scheme://$_host:$_port';

  // Auth
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String me = '/api/auth/me';

  // Health Records
  static const String healthRecords = '/api/health/records';
  static String healthRecord(String id) => '/api/health/records/$id';
  static const String latestRecords = '/api/health/records/latest';

  // Chat
  static const String chat = '/api/consult/chat';
  static const String chatStream = '/api/consult/chat/stream';
  static const String chatHistory = '/api/consult/chat/history';
  static const String conversations = '/api/consult/conversations';
  static String conversationDetail(String id) => '/api/consult/conversations/$id';

  // Voice
  static const String voiceChat = '/api/consult/voice/chat';
  static const String voiceChatStream = '/api/consult/voice/chat/stream';
  static const String voiceWs = '/api/consult/voice/ws';
}
