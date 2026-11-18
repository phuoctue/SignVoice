import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/navigation.dart';
import '../providers/auth_provider.dart';

String guestDate(DateTime? date) => date == null
    ? 'chưa xác định từ máy chủ'
    : DateFormat('HH:mm dd/MM/yyyy').format(date.toLocal());

const guestLoginNotice =
    'Dữ liệu khách KHÔNG được chuyển sang tài khoản có sẵn. Đăng nhập có thể khiến bạn không thể quay lại dữ liệu khách này. Đăng ký tài khoản mới để giữ dữ liệu; bỏ dữ liệu cần xác nhận riêng.';
const guestTrialConsent =
    'Bạn được dùng thử 10 phút. Đóng ứng dụng không làm dừng hay đặt lại thời gian. Dữ liệu khách được giữ 7 ngày; muốn giữ lâu hơn, hãy tạo tài khoản. Mỗi thiết bị được thử lại sau 24 giờ.';
const guestPrivacySummary =
    'Dữ liệu khách được giữ 7 ngày. Sau đó bạn không xem hay chuyển được nữa, nhưng vẫn có thể tự xóa. Bản sao lưu dùng để khôi phục sự cố có thể còn dữ liệu tới khoảng 3 tháng.';
const guestPrivacyNotice =
    'Dữ liệu khách được giữ trong 7 ngày từ khi cấp lượt thử. Sau hạn này bạn không thể xem hay chuyển dữ liệu, nhưng vẫn có thể yêu cầu xóa dữ liệu còn lại nếu phiên khách còn hợp lệ. Việc dọn khỏi hệ thống đang dùng có mục tiêu trong 24 giờ tiếp theo; sự cố hoặc thời gian dừng có thể làm chậm. Khi xác nhận bỏ dữ liệu, máy chủ xóa trong giao dịch xử lý yêu cầu và chỉ báo thành công sau khi hoàn tất. Bản sao lưu chỉ phục vụ khôi phục sự cố, không dùng lại dữ liệu khách cho sản phẩm, được hạn chế truy cập và có thể còn dữ liệu đến hết thời hạn lưu bản sao. Khi lịch chạy đầy đủ, bản sao cũ nhất có thể khoảng 92 ngày từ ngày sao lưu (khoảng 99 ngày hoặc hơn từ lúc cấp lượt); hiện chưa có giới hạn tối đa hữu hạn khi bỏ lỡ lịch hoặc dọn bản sao bị gián đoạn. Thông tin phiên giới hạn như thiết bị/IP có thể còn tối đa 90 ngày làm hồ sơ bảo mật.';

Future<bool> confirmGuestLogout(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final epoch = auth.accountEpoch;
  final guest = auth.user?.isGuest == true;
  final deadline = auth.conversionDeadline;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      scrollable: true,
      title: Text(guest ? 'Thoát chế độ khách?' : 'Đăng xuất?'),
      content: Text(
        guest
            ? auth.trial == null
                  ? 'Bạn không thể quay lại dữ liệu khách này sau khi thoát. Chưa tải được hạn giữ dữ liệu… Đăng ký tài khoản mới ngay khi còn quyền chuyển để giữ dữ liệu.'
                  : deadline == null ||
                        (auth.trial?.dataState == 'legacy_unknown' &&
                            auth.trial?.dataRetainedUntil == null)
                  ? 'Bạn không thể quay lại dữ liệu khách này sau khi thoát. Máy chủ chưa xác định hạn giữ dữ liệu của phiên này; không thể hẹn ngày dọn dữ liệu. '
                        '${auth.user?.legacyGuestSessionCutoffAt == null ? '' : 'Phiên khách hết hạn: ${guestDate(auth.user?.legacyGuestSessionCutoffAt)}. '}'
                        'Đăng ký tài khoản mới ngay khi còn quyền chuyển để giữ dữ liệu.'
                  : 'Bạn không thể quay lại dữ liệu khách này sau khi thoát. Hạn giữ hoặc chuyển dữ liệu của phiên này là ${guestDate(deadline)}. Dữ liệu được dọn theo hạn giữ dữ liệu của máy chủ (mục tiêu trong 24 giờ sau hạn giữ, có thể chậm khi sự cố). Đăng ký tài khoản mới ngay khi còn quyền chuyển để giữ dữ liệu.'
            : 'Bạn sẽ quay về màn hình đăng nhập.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Ở lại'),
        ),
        if (guest && auth.guestAllows('convert'))
          TextButton(
            onPressed: () {
              Navigator.pop(dialog, false);
              openScreen(context, 'S06');
            },
            child: const Text('Đăng ký để giữ dữ liệu'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Đăng xuất'),
        ),
      ],
    ),
  );
  return result == true && context.mounted && auth.accountEpoch == epoch;
}

class GuestDataPanel extends StatefulWidget {
  const GuestDataPanel({
    super.key,
    this.compact = false,
    this.collapsed = false,
    this.returnRoute,
  });
  final bool compact;
  final bool collapsed;
  final String? returnRoute;
  @override
  State<GuestDataPanel> createState() => _GuestDataPanelState();
}

class _GuestDataPanelState extends State<GuestDataPanel> {
  bool webDismissed = false;
  @override
  void initState() {
    super.initState();
    if (kIsWeb && widget.compact) {
      SharedPreferences.getInstance().then((prefs) {
        final until = prefs.getInt('guest_notice_dismissed_until');
        if (mounted &&
            until != null &&
            DateTime.now().millisecondsSinceEpoch < until) {
          setState(() => webDismissed = true);
        }
      });
    }
  }

  Future<void> confirmLoss(AuthProvider auth, {required bool replace}) async {
    final epoch = auth.accountEpoch;
    final version = auth.trial?.dataVersion;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(
          replace ? 'Bỏ dữ liệu và bắt đầu lượt mới?' : 'Bỏ dữ liệu khách?',
        ),
        content: Text(
          'Chỉ dữ liệu của khách hiện tại, lượt cấp ${guestDate(auth.trial?.startedAt)}, sẽ bị xóa: hội thoại, lịch sử tìm kiếm, tiến độ học, từ cá nhân, bộ sưu tập/ghi chú, yêu thích và thông báo nếu có. Không thể hoàn tác. Dữ liệu tài khoản có sẵn không bị xóa. ${replace ? 'Lượt mới bắt đầu trống và kéo dài 10 phút. $guestTrialConsent' : 'Bỏ dữ liệu không cấp thêm lượt thử.'}',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            key: const ValueKey('guest-confirm-loss'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              replace ? 'Bỏ dữ liệu và bắt đầu' : 'Xác nhận bỏ dữ liệu khách',
            ),
          ),
        ],
      ),
    );
    if (!mounted ||
        accepted != true ||
        auth.accountEpoch != epoch ||
        auth.trial?.dataVersion != version) {
      return;
    }
    if (replace) {
      final success = await auth.replaceGuest();
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'Chưa xác nhận được lượt mới.'),
          ),
        );
      }
    } else {
      await auth.discardGuest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final trial = auth.trial;
    final dated = auth.user?.legacyGuestSessionCutoffAt != null;
    final dismissible =
        widget.compact &&
        !dated &&
        trial?.dataState == 'trial_active' &&
        !auth.trialExpired;
    if (dismissible && (auth.noticeDismissed || webDismissed)) {
      return const SizedBox.shrink();
    }
    final stale = auth.trialError != null || auth.trialLoading;
    final seconds = (auth.trialRemaining.inMilliseconds / 1000).ceil();
    Widget action(String key, String label, VoidCallback onPressed) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton(
        key: ValueKey(key),
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: auth.isLoading || auth.guestOperationBusy ? null : onPressed,
        child: Text(label),
      ),
    );
    final panel = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              auth.user == null && auth.guestOperationMessage != null
                  ? 'Kết quả yêu cầu dữ liệu khách'
                  : trial?.dataState == 'legacy_unknown' &&
                        trial?.dataRetainedUntil == null
                  ? 'Chưa xác định thời hạn dữ liệu khách'
                  : trial?.dataState == 'expired'
                  ? 'Đã hết quyền truy cập dữ liệu khách'
                  : auth.trialExpired
                  ? 'Lượt thử đã kết thúc'
                  : 'Bạn đang dùng tài khoản khách',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (trial?.dataState == 'trial_active' &&
                !auth.trialExpired &&
                !stale)
              Text(
                'Dùng thử · còn ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                semanticsLabel: 'Lượt thử đang hoạt động. Thời gian còn lại hiển thị trên màn hình.',
              ),
            if (trial != null) ...[
              if (stale)
                const Text(
                  'Thông tin xác nhận gần nhất; chưa kiểm tra lại được với máy chủ.',
                ),
              Text('Hạn giữ dữ liệu: ${guestDate(trial.dataRetainedUntil)}'),
              Text(
                'Lượt thử tiếp theo: ${guestDate(trial.nextTrialAvailableAt)}',
              ),
              if (dated)
                Text(
                  'Phiên khách hết hạn: ${guestDate(auth.user?.legacyGuestSessionCutoffAt)}. Hạn chuyển tài khoản: ${guestDate(auth.conversionDeadline)}.',
                ),
            ],
            if (auth.trialLoading || auth.guestOperationBusy)
              const LinearProgressIndicator(
                semanticsLabel: 'Đang kiểm tra với máy chủ',
              ),
            if (auth.trialError != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  'Không thể kiểm tra trạng thái. ${auth.trialError}',
                ),
              ),
              action('guest-retry', 'Thử lại', () => auth.loadGuestTrial()),
            ],
            if (auth.guestOperationMessage != null)
              Semantics(
                liveRegion: true,
                child: Text(auth.guestOperationMessage!),
              ),
            if (auth.errorMessage != null && !auth.isAuthenticated)
              Text(auth.errorMessage!),
            if (auth.guestOperationUnknown && auth.isAuthenticated)
              action(
                'guest-reconcile',
                'Kiểm tra trạng thái',
                auth.reconcileGuestOperation,
              ),
            if (!widget.compact &&
                auth.isAuthenticated &&
                !auth.trialLoading &&
                !auth.guestOperationUnknown &&
                auth.trialError == null)
              action(
                'guest-refresh',
                'Cập nhật trạng thái',
                () => auth.loadGuestTrial(),
              ),
            if (auth.guestAllows('convert'))
              action(
                'guest-convert',
                'Đăng ký tài khoản mới để giữ dữ liệu',
                () => openScreen(context, 'S06'),
              ),
            if (!widget.compact &&
                (auth.user == null ||
                    (!stale && trial?.dataState == 'expired')))
              action(
                'guest-register-fresh',
                'Tạo tài khoản mới không giữ dữ liệu khách',
                () => openScreen(context, 'S06'),
              ),
            if (!widget.compact && auth.guestAllows('discard'))
              action(
                'guest-discard',
                'Bỏ dữ liệu khách',
                () => confirmLoss(auth, replace: false),
              ),
            if (!widget.compact && auth.guestAllows('new_trial'))
              action(
                'guest-replace',
                'Bắt đầu lượt thử mới 10 phút',
                () => confirmLoss(auth, replace: true),
              ),
            if (!widget.compact) ...[
              const Text(guestLoginNotice),
              action(
                'guest-login',
                'Đăng nhập tài khoản có sẵn',
                () => openScreen(
                  context,
                  authLocation(returnRoute: widget.returnRoute),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(guestPrivacySummary),
              ),
              ExpansionTile(
                title: const Text('Chi tiết'),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(guestPrivacyNotice),
                  ),
                ],
              ),
              if (auth.user?.isGuest == true)
                action('guest-logout', 'Thoát chế độ khách', () async {
                  if (await confirmGuestLogout(context)) await auth.logout();
                }),
            ],
            if (dismissible)
              TextButton(
                onPressed: () async {
                  auth.dismissGuestNotice();
                  if (kIsWeb) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt(
                      'guest_notice_dismissed_until',
                      DateTime.now()
                          .add(const Duration(hours: 24))
                          .millisecondsSinceEpoch,
                    );
                  }
                },
                child: const Text('Ẩn nhắc nhở'),
              ),
          ],
        ),
      ),
    );
    if (!widget.collapsed || dated) return panel;
    return Material(
      child: ExpansionTile(
        title: Text(
          trial?.dataState == 'trial_active' && !auth.trialExpired && !stale
              ? 'Dùng thử · còn ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
              : 'Dữ liệu khách và thời hạn',
          semanticsLabel:
              'Dữ liệu khách. Mở để xem thời gian còn lại và hạn giữ dữ liệu.',
        ),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .3,
            ),
            child: SingleChildScrollView(child: panel),
          ),
        ],
      ),
    );
  }
}
