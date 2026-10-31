import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../core/navigation.dart';
import '../../widgets/ui.dart';
import '../../services/auth/collection_return_route.dart';

String oauthErrorMessage(String code) => switch (code) {
  'OAUTH_CANCELLED' => 'Bạn đã hủy đăng nhập. Có thể thử lại hoặc dùng email.',
  'OAUTH_ACCOUNT_COLLISION' => 'Email này đã có tài khoản. Hãy đăng nhập bằng phương thức đã đăng ký. Liên kết tài khoản cần xác minh riêng.',
  'USER_DISABLED' => 'Tài khoản đã bị tạm ngưng hoặc xóa.',
  'OAUTH_STATE_INVALID' =>
    'Phiên đăng nhập đã hết hạn hoặc không hợp lệ. Vui lòng bắt đầu lại.',
  _ => 'Không hoàn tất được đăng nhập Google/Facebook. Vui lòng thử lại.',
};

class OAuthCompleteScreen extends StatefulWidget {
  const OAuthCompleteScreen({super.key, this.error});
  final String? error;
  @override
  State<OAuthCompleteScreen> createState() => _OAuthCompleteScreenState();
}

class _OAuthCompleteScreenState extends State<OAuthCompleteScreen> {
  String? message;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => complete());
  }

  Future<void> complete() async {
    if (widget.error != null) {
      setState(() {
        busy = false;
        message = oauthErrorMessage(widget.error!);
      });
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.completeOAuth();
    if (!mounted) return;
    if (success) {
      openRoot(context, consumeCollectionReturnRoute() ?? 'S08');
    } else {
      setState(() {
        busy = false;
        message = auth.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Đăng nhập Google/Facebook',
    showBack: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 18),
          const Text(
            'Đang xác minh phiên đăng nhập…',
            textAlign: TextAlign.center,
          ),
        ] else ...[
          Notice(message ?? 'Đăng nhập thất bại.'),
          const SizedBox(height: 18),
          AppButton(
            'Quay lại đăng nhập',
            onPressed: () => openRoot(context, 'S05'),
          ),
        ],
      ],
    ),
  );
}
