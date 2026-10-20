import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/ai_config.dart';
import '../../services/lm_studio_service.dart';

class ImageAnalysisScreen extends StatefulWidget {
  const ImageAnalysisScreen({super.key});

  @override
  State<ImageAnalysisScreen> createState() => _ImageAnalysisScreenState();
}

class _ImageAnalysisScreenState extends State<ImageAnalysisScreen> {
  final LMStudioService _aiService = LMStudioService();
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _modelId = 'qwen2.5-vl-7b-instruct';
  String _result = '';
  bool _isLoading = false;
  String _connectionStatus = 'Đang kiểm tra kết nối...';

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    try {
      final models = await _aiService.getModels();
      if (mounted) {
        setState(() {
          if (models.contains('qwen2.5-vl-7b-instruct')) {
            _modelId = 'qwen2.5-vl-7b-instruct';
          } else if (models.isNotEmpty) {
            _modelId = models.first;
          }
          _connectionStatus = 'Đã kết nối LM Studio (Model: $_modelId)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionStatus = 'Chưa kết nối được LM Studio: $e';
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _result = '';
      });

      // Tự động phân tích ngay sau khi chọn ảnh
      await _analyzeCurrentPicture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh: $e')),
      );
    }
  }

  Future<void> _analyzeCurrentPicture() async {
    if (_imageBytes == null) return;

    setState(() {
      _isLoading = true;
      _result = 'AI đang quan sát và phân tích hình ảnh...';
    });

    try {
      final model = _modelId ?? 'qwen2.5-vl-7b-instruct';
      const prompt = '''
Bạn là chuyên gia ngôn ngữ ký hiệu và phân tích thị giác AI. Hãy phân tích hình ảnh này bằng tiếng Việt:
1. Nhận diện các cử chỉ tay, động tác hoặc ký hiệu (Sign Language).
2. Mô tả rõ nét hình dạng bàn tay, hướng lòng bàn tay và các ngón tay.
3. Dự đoán từ ngữ hoặc thông điệp tương ứng của ký hiệu này (nếu có).
4. Nhận xét ngắn gọn, rõ ràng, dễ hiểu.
''';

      final response = await _aiService.chat(
        modelId: model,
        prompt: prompt,
        imageBytes: _imageBytes,
      );

      if (mounted) {
        setState(() {
          _result = response;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = 'Lỗi phân tích: $e\n\n(Lưu ý: Đảm bảo LM Studio đã tải xong GGUF runtime và Server đang mở)';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showServerSettingsDialog() {
    final controller = TextEditingController(text: AIConfig.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cài đặt AI Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập địa chỉ IP & Port của laptop đang chạy LM Studio:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'http://10.12.58.197:1234/v1',
                labelText: 'Base URL',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              AIConfig.customBaseUrl = controller.text.trim();
              Navigator.pop(ctx);
              _checkServer();
            },
            child: const Text('Lưu & Kết nối lại'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích ký hiệu AI (Vision)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Đổi IP Server',
            onPressed: _showServerSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Kiểm tra lại kết nối',
            onPressed: _checkServer,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trạng thái server
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _connectionStatus.startsWith('Đã kết nối')
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _connectionStatus.startsWith('Đã kết nối')
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _connectionStatus.startsWith('Đã kết nối')
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: _connectionStatus.startsWith('Đã kết nối')
                        ? Colors.green
                        : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionStatus,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Khung hiển thị ảnh
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sign_language,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có ảnh ký hiệu để phân tích',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // Nút bấm chụp ảnh và chọn từ thư viện
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Chụp ảnh'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Thư viện'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],

            // Kết quả phân tích
            if (_result.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Kết quả từ mô hình Vision:',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SelectableText(
                        _result,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
