class MediaAccessException implements Exception {
  const MediaAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

MediaAccessException mediaAccessError(
  String reason, {
  String device = 'camera',
}) {
  final code = reason.toLowerCase();
  if (code.contains('insecure') || code.contains('securecontext')) {
    return MediaAccessException(
      'Truy cập bằng HTTPS hoặc http://localhost để dùng $device. Địa chỉ HTTP qua IP mạng không được trình duyệt cấp quyền.',
    );
  }
  if (code.contains('notallowed') ||
      code.contains('permission') ||
      code.contains('accessdenied') ||
      code.contains('securityerror')) {
    return MediaAccessException(
      'Quyền $device đang bị chặn hoặc chưa được cấp. Trên Chrome, mở biểu tượng bên trái địa chỉ → Cài đặt trang web → $device → Cho phép, rồi bấm Thử lại. Nếu vẫn bị chặn, kiểm tra quyền trong cài đặt hệ điều hành.',
    );
  }
  if (code.contains('notfound') ||
      code.contains('nodevice') ||
      code.contains('no device')) {
    return MediaAccessException(
      'Không tìm thấy $device. Kiểm tra thiết bị đã kết nối và được hệ điều hành nhận.',
    );
  }
  if (code.contains('notreadable') ||
      code.contains('trackstart') ||
      code.contains('in use')) {
    return MediaAccessException(
      'Không mở được $device. Thiết bị có thể đang được ứng dụng khác dùng; hãy đóng ứng dụng đó rồi Thử lại.',
    );
  }
  return MediaAccessException(
    'Không mở được $device. Kiểm tra quyền trang web, quyền hệ điều hành và thiết bị, rồi Thử lại.',
  );
}
