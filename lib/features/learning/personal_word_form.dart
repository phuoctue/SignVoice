import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';
import 'record_video_dialog.dart';

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
  const PersonalWordForm({
    super.key,
    required this.service,
    this.word,
    this.videoRecorder,
  });
  final LearningService service;
  final LearningRecord? word;
  final Future<XFile?> Function(BuildContext)? videoRecorder;
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
  late String video = widget.word?['videoUrl'] as String? ?? '';
  String? videoName;
  late String image = widget.word?['imageUrl'] as String? ?? '';
  String? error;
  bool saving = false, picking = false, uploadingVideo = false;
  bool get busy => saving || picking || uploadingVideo;
  @override
  void dispose() {
    for (final c in [name, meaning, example]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickVideo({bool record = false}) async {
    setState(() {
      uploadingVideo = true;
      error = null;
    });
    try {
      final file = record
          ? await (widget.videoRecorder ?? recordLearningVideo)(context)
          : await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length > 1024 * 1024 * 1024) {
        throw StateError('Video cần nhỏ hơn hoặc bằng 1 GB.');
      }
      if (!mounted) return;
      final url = await widget.service.uploadVideo(file.openRead, length);
      if (mounted) {
        setState(() {
          video = url;
          videoName = record
              ? 'Video vừa quay'
              : file.name.split(RegExp(r'[/\\]')).last;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : e is StateError
              ? e.message
              : 'Chưa thêm được video. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => uploadingVideo = false);
    }
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
    if (busy) return;
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
        'imageUrl': image,
        'videoUrl': video,
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
          onPressed: busy ? null : () => Navigator.pop(context),
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
                  onPressed: busy ? null : () => setState(() => image = ''),
                  icon: const Icon(Icons.close),
                  label: const Text('Bỏ ảnh'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: busy ? null : pick,
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
              const Heading('Video ký hiệu (không bắt buộc)', size: 16),
              const SizedBox(height: 8),
              if (video.isNotEmpty) ...[
                LearningWordContent({
                  '_id': widget.word?['_id'] ?? 'preview',
                  'word': name.text,
                  'videoUrl': video,
                  'imageUrl': image,
                }, showMeaning: false),
                if (videoName != null) Text(videoName!),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          video = '';
                          videoName = null;
                        }),
                  icon: const Icon(Icons.close),
                  label: const Text('Bỏ video'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: busy ? null : () => pickVideo(),
                icon: const Icon(Icons.video_library_outlined),
                label: Text(video.isEmpty ? 'Chọn video từ máy' : 'Đổi video'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => pickVideo(record: true),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Quay video mới'),
              ),
              if (uploadingVideo)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Đang tải và xử lý video…'),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: BodyText(
                  'Chọn video đã tải về hoặc tự quay ký hiệu. Tối đa 1 GB; chỉ tài khoản của bạn xem được.',
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
                onPressed: busy ? null : save,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
