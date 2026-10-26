import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class AvatarSelection {
  const AvatarSelection(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
  String get dataUrl => 'data:image/$mime;base64,${base64Encode(bytes)}';
}

Future<AvatarSelection?> pickAvatarImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 80,
  );
  if (file == null) return null;
  if (await file.length() > 512 * 1024) {
    throw StateError('Chọn ảnh nhỏ hơn 512 KB.');
  }
  final bytes = await file.readAsBytes();
  final mime = bytes.length >= 12 && bytes[0] == 137 && bytes[1] == 80
      ? 'png'
      : bytes.length >= 12 && bytes[0] == 255 && bytes[1] == 216
      ? 'jpeg'
      : bytes.length >= 12 &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
      ? 'webp'
      : null;
  if (mime == null) throw StateError('Chọn ảnh JPG, PNG hoặc WebP.');
  return AvatarSelection(bytes, mime);
}
