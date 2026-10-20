import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/lm_studio_service.dart';

class AITestPage extends StatefulWidget {
  const AITestPage({super.key});

  @override
  State<AITestPage> createState() => _AITestPageState();
}

class _AITestPageState extends State<AITestPage> {
  final ai = LMStudioService();
  final picker = ImagePicker();
  final promptController = TextEditingController(
    text: 'Hãy giới thiệu về khả năng nhận diện hình ảnh của bạn bằng tiếng Việt.',
  );
  String result = 'Chưa kết nối';
  String? modelId;
  bool loading = false;

  Future<void> connect() async {
    setState(() {
      loading = true;
      result = 'Đang kết nối...';
    });
    try {
      final models = await ai.getModels();
      if (models.isEmpty) {
        throw Exception('Không tìm thấy mô hình AI đang load');
      }
      setState(() {
        modelId = models.first;
        result = 'Kết nối thành công!\nModel ID: $modelId';
      });
    } catch (e) {
      setState(() => result = 'Lỗi kết nối:\n$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> askAI() async {
    if (modelId == null) {
      await connect();
      if (modelId == null) return;
    }
    setState(() {
      loading = true;
      result = 'AI đang xử lý văn bản...';
    });
    try {
      final answer = await ai.chat(
        modelId: modelId!,
        prompt: promptController.text,
      );
      setState(() => result = answer);
    } catch (e) {
      setState(() => result = 'Lỗi AI:\n$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> pickAndAnalyzeImage(ImageSource source) async {
    if (modelId == null) {
      await connect();
      if (modelId == null) return;
    }
    final XFile? image = await picker.pickImage(
      source: source,
    );
    if (image == null) {
      setState(() => result = 'Người dùng chưa chọn ảnh');
      return;
    }
    setState(() {
      loading = true;
      result = 'AI đang phân tích hình ảnh...';
    });
    try {
      final bytes = await image.readAsBytes();
      final answer = await ai.chat(
        modelId: modelId!,
        prompt: '''
Hãy phân tích hình ảnh bằng tiếng Việt:
1. Nhận diện các đối tượng và cử chỉ tay (nếu có).
2. Mô tả chi tiết bối cảnh.
3. Giải thích dựa trên bằng chứng trực quan.
''',
        imageBytes: bytes,
      );
      setState(() => result = answer);
    } catch (e) {
      setState(() => result = 'Lỗi AI Vision:\n$e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LM Studio Local AI (Test Page)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ElevatedButton(
              onPressed: loading ? null : connect,
              child: const Text('1. Kiểm tra kết nối'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: promptController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Câu hỏi hoặc Prompt văn bản',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loading ? null : askAI,
              child: const Text('2. Gửi câu hỏi văn bản'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : () => pickAndAnalyzeImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('3. Chụp & Phân tích'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : () => pickAndAnalyzeImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Chọn ảnh & Phân tích'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            SelectableText(
              result,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
