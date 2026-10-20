import 'package:flutter/material.dart';

const screenNames = <String, String>{
  'S01': 'Splash',
  'S02': 'Onboarding 1',
  'S03': 'Onboarding 2',
  'S04': 'Onboarding 3',
  'S05': 'Đăng nhập',
  'S06': 'Đăng ký',
  'S07': 'Quên mật khẩu',
  'S08': 'Trang chủ',
  'S09': 'Cấp quyền Camera',
  'S10': 'Camera sẵn sàng',
  'S11': 'Nhận diện thành công',
  'S12': 'Nhận diện thất bại',
  'S13': 'Tạo câu',
  'S14': 'Phát giọng nói',
  'S15': 'Cấp quyền Micro',
  'S16': 'Microphone sẵn sàng',
  'S17': 'Đang lắng nghe',
  'S18': 'Kết quả văn bản',
  'S19': 'Văn bản toàn màn hình',
  'S20': 'Lịch sử hội thoại',
  'S21': 'Chi tiết lịch sử',
  'S22': 'Từ điển ký hiệu',
  'S23': 'Chi tiết ký hiệu',
  'S24': 'Yêu thích',
  'S25': 'Cá nhân',
  'S26': 'Chỉnh sửa hồ sơ',
  'S27': 'Cài đặt giọng nói',
  'S28': 'Giao diện & Trợ năng',
  'S29': 'Đồng bộ dữ liệu',
  'S30': 'Quyền riêng tư',
  'S31': 'Thông tin ứng dụng',
  'SS01': 'Loading',
  'SS02': 'Empty State',
  'SS03': 'Success',
  'SS04': 'Error',
  'SS05': 'Offline',
  'SS06': 'Quyền bị từ chối',
  'ai_vision': 'Camera ký hiệu',
};

void openScreen(BuildContext context, String id, {bool replace = false}) {
  if (replace) {
    Navigator.of(context).pushReplacementNamed(id);
  } else {
    Navigator.of(context).pushNamed(id);
  }
}

void openRoot(BuildContext context, String id) =>
    Navigator.of(context).pushNamedAndRemoveUntil(id, (route) => false);
void backOrHome(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    openRoot(context, 'S08');
  }
}
