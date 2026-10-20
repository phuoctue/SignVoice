import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/ai_config.dart';

class LMStudioService {
  final String baseUrl;
  final String? apiToken;

  LMStudioService({
    String? baseUrl,
    this.apiToken,
  }) : baseUrl = baseUrl ?? AIConfig.baseUrl;

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (apiToken != null && apiToken!.isNotEmpty)
          'Authorization': 'Bearer $apiToken',
      };

  /// 1. Kiểm tra server và lấy danh sách model
  Future<List<String>> getModels() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/models'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'LM Studio HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final models = data['data'] as List<dynamic>;
    return models.map((m) => m['id'].toString()).toList();
  }

  /// 2. Gửi câu hỏi kèm hình ảnh qua Chat Completions (Vision)
  Future<String> chat({
    required String modelId,
    required String prompt,
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final List<Map<String, dynamic>> content = [
      {
        'type': 'text',
        'text': prompt,
      }
    ];

    // Chuyển ảnh sang dạng Data URL Base64 nếu có
    if (imageBytes != null) {
      final imageBase64 = base64Encode(imageBytes);
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$mimeType;base64,$imageBase64',
        },
      });
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: headers,
          body: jsonEncode({
            'model': modelId,
            'messages': [
              {
                'role': 'user',
                'content': content,
              }
            ],
            'temperature': 0.2,
            'max_tokens': 1200,
            'stream': false,
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception(
        'AI Error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final message = data['choices'][0]['message'];
    return message['content']?.toString() ?? '';
  }
}
