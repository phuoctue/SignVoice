import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

Future<bool> editPersonalWord(
  BuildContext context,
  LearningService service, {
  LearningRecord? word,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PersonalWordForm(service: service, word: word),
    ) ??
    false;

class PersonalWordForm extends StatefulWidget {
  const PersonalWordForm({super.key, required this.service, this.word});
  final LearningService service;
  final LearningRecord? word;
  @override
  State<PersonalWordForm> createState() => _PersonalWordFormState();
}

class _PersonalWordFormState extends State<PersonalWordForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.word?['word'] as String? ?? '',
  );
  late final meaning = TextEditingController(
    text: widget.word?['definition'] as String? ?? '',
  );
  late final example = TextEditingController(
    text: widget.word?['usageExample'] as String? ?? '',
  );
  late final notes = TextEditingController(
    text: widget.word?['notes'] as String? ?? '',
  );
  late final video = TextEditingController(
    text: widget.word?['videoUrl'] as String? ?? '',
  );
  late String image = widget.word?['imageUrl'] as String? ?? '';
  String? error;
  bool saving = false, picking = false;
  @override
  void dispose() {
    for (final c in [name, meaning, example, notes, video]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 1000000) {
        throw StateError('Ảnh cần nhỏ hơn 1 MB. Hãy chọn ảnh nhỏ hơn.');
      }
      final type = bytes.length > 12 && bytes[0] == 0x89 && bytes[1] == 0x50
          ? 'png'
          : bytes.length > 12 && bytes[0] == 0xff && bytes[1] == 0xd8
          ? 'jpeg'
          : bytes.length > 12 &&
                ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
          ? 'webp'
          : null;
      if (type == null) throw StateError('Hãy chọn ảnh JPG, PNG hoặc WebP.');
      if (mounted) {
        setState(
          () => image = 'data:image/$type;base64,${base64Encode(bytes)}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Chưa chọn được ảnh. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.service.saveWord({
        'word': name.text.trim(),
        'definition': meaning.text.trim(),
        'usageExample': example.text.trim(),
        'notes': notes.text.trim(),
        'imageUrl': image,
        'videoUrl': video.text.trim(),
      }, id: widget.word?['_id'] as String?);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa lưu được từ. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .93,
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.word == null ? 'Tạo từ của tôi' : 'Chỉnh sửa từ'),
        leading: IconButton(
          tooltip: 'Đóng',
          onPressed: saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BodyText(
                'Tạo thẻ học theo cách của bạn. Chỉ tài khoản của bạn nhìn thấy những từ này.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Từ hoặc cụm từ *',
                  hintText: 'Ví dụ: Xin chào',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Nhập từ bạn muốn học.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: meaning,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Ý nghĩa *'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Thêm ý nghĩa để dễ ôn tập.'
                    : null,
              ),
              const SizedBox(height: 8),
              if (image.isNotEmpty) ...[
                SignPhoto(image, word: name.text, height: 160),
                TextButton.icon(
                  onPressed: saving ? null : () => setState(() => image = ''),
                  icon: const Icon(Icons.close),
                  label: const Text('Bỏ ảnh'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: saving || picking ? null : pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  picking
                      ? 'Đang chọn ảnh...'
                      : image.isEmpty
                      ? 'Thêm ảnh ký hiệu'
                      : 'Đổi ảnh',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: example,
                maxLength: 1000,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Câu ví dụ (không bắt buộc)',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: video,
                maxLength: 2000,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Link video HTTPS (không bắt buộc)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final url = Uri.tryParse(v.trim());
                  return url?.scheme == 'https' && url!.host.isNotEmpty
                      ? null
                      : 'Nhập link bắt đầu bằng https://';
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: notes,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mẹo ghi nhớ / nguồn tham khảo',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Notice(error!),
                ),
              AppButton(
                'Lưu từ',
                icon: Icons.check,
                busy: saving,
                onPressed: saving || picking ? null : save,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
