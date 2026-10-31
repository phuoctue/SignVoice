import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../widgets/ui.dart';
import '../../features/learning/collection_widgets.dart';
import '../../features/learning/learning_widgets.dart';
import 'admin_ui.dart';

const moderationLabels = {
  'CLEAR': 'Cho phép chia sẻ',
  'HIDDEN': 'Ẩn khỏi khám phá',
  'BLOCKED': 'Chặn chia sẻ',
};
const reportStatusLabels = {
  'OPEN': 'Chưa xử lý',
  'RESOLVED': 'Đã xử lý',
  'DISMISSED': 'Không ghi nhận vi phạm',
};
String moderationDate(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  return date == null
      ? ''
      : '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class CollectionModerationScreen extends StatefulWidget {
  const CollectionModerationScreen({super.key, this.id});
  final String? id;
  @override
  State<CollectionModerationScreen> createState() =>
      _CollectionModerationScreenState();
}

class _CollectionModerationScreenState
    extends State<CollectionModerationScreen> {
  final search = TextEditingController();
  AdminRecord? data, collection;
  String status = 'ALL', reportStatus = 'OPEN', query = '';
  String? error;
  bool loading = true, acting = false;
  int page = 1, panel = 0, request = 0;
  final opened = <String>{};
  bool get detail => widget.id != null;
  AdminWorkspaceService get service => context.read<AdminWorkspaceService>();
  List<AdminRecord> get items => (data?['items'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  int get pages => (data?['pagination']?['pages'] as num? ?? 1).toInt();
  int get total => (data?['pagination']?['total'] as num? ?? 0).toInt();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    request++;
    search.dispose();
    super.dispose();
  }

  Future<void> load({int? nextPage, bool clear = false}) async {
    final ticket = ++request,
        auth = context.read<AuthProvider>(),
        account = context.read<AuthProvider>().accountEpoch;
    setState(() {
      page = nextPage ?? page;
      loading = true;
      error = null;
      if (clear) data = null;
    });
    final suffix = !detail
        ? ''
        : '/${widget.id}${panel == 1
              ? '/reports'
              : panel == 2
              ? '/history'
              : ''}';
    try {
      final result = await service.collectionModerationRead(
        suffix,
        page: page,
        search: !detail ? query : '',
        status: !detail
            ? status
            : panel == 1
            ? reportStatus
            : null,
      );
      if (!mounted || ticket != request || auth.accountEpoch != account) return;
      setState(() {
        data = result;
        if (result['collection'] is Map) {
          collection = Map<String, dynamic>.from(result['collection'] as Map);
        }
      });
    } catch (e) {
      if (mounted && ticket == request && auth.accountEpoch == account) {
        setState(() => error = collectionError(e));
      }
    } finally {
      if (mounted && ticket == request) setState(() => loading = false);
    }
  }

  Future<void> choosePanel(int value) async {
    if (acting || value == panel) return;
    setState(() => panel = value);
    await load(nextPage: 1, clear: true);
  }

  Future<void> changeState(String state) async {
    if (acting || collection == null) return;
    final version = (collection!['moderationVersion'] as num? ?? 0).toInt();
    setState(() => acting = true);
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModerationReasonDialog(
        title: state == 'CLEAR'
            ? 'Khôi phục quyền chia sẻ?'
            : state == 'HIDDEN'
            ? 'Ẩn khỏi khám phá?'
            : 'Chặn chia sẻ bộ?',
        explanation: state == 'CLEAR'
            ? 'Khôi phục theo lựa chọn hiện tại của chủ bộ. Bộ đã rút về riêng tư sẽ không tự đăng lại.'
            : state == 'HIDDEN'
            ? 'Bộ sẽ không xuất hiện trong khám phá. Liên kết vẫn hoạt động; nếu bộ đang bị chặn, thao tác này sẽ mở lại liên kết. Dữ liệu gốc được giữ.'
            : 'Chặn khám phá, liên kết, QR và lưu bản sao mới. Chủ bộ vẫn giữ toàn bộ dữ liệu.',
        submitLabel: state == 'CLEAR'
            ? 'Khôi phục'
            : state == 'HIDDEN'
            ? 'Ẩn bộ'
            : 'Chặn chia sẻ',
        danger: state != 'CLEAR',
        onSave: (reason) =>
            service.moderateCollection(widget.id!, state, reason, version),
      ),
    );
    if (!mounted) return;
    setState(() => acting = false);
    if (changed == true) toast(context, 'Đã cập nhật trạng thái bộ.');
    // Also refresh after a cancelled stale dialog so the next action uses the latest version.
    if (panel == 0) {
      await load();
    } else {
      try {
        final result = await service.collectionModerationRead('/${widget.id}');
        if (mounted) {
          setState(
            () => collection = Map<String, dynamic>.from(
              result['collection'] as Map,
            ),
          );
        }
      } catch (e) {
        if (mounted) toast(context, collectionError(e));
      }
      if (mounted) await load();
    }
  }

  Future<void> resolve(AdminRecord row, String state) async {
    if (acting) return;
    setState(() => acting = true);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModerationReasonDialog(
        title: state == 'RESOLVED'
            ? 'Hoàn tất báo cáo?'
            : 'Không ghi nhận vi phạm?',
        explanation: 'Ghi rõ kết quả kiểm tra. Xử lý báo cáo không tự thay đổi trạng thái chia sẻ của bộ; bạn thực hiện việc ẩn/chặn riêng sau khi xem nội dung.',
        submitLabel: 'Lưu kết quả',
        onSave: (reason) => service.resolveCollectionReport(
          widget.id!,
          '${row['_id']}',
          state,
          reason,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => acting = false);
    if (saved == true) {
      toast(context, 'Đã lưu kết quả xử lý báo cáo.');
      await load();
    }
  }

  Widget stateLabel(AdminRecord row) => Text(
    moderationLabels['${row['moderationState']}'] ?? moderationLabels['CLEAR']!,
    style: TextStyle(
      fontWeight: FontWeight.w600,
      color: row['moderationState'] == 'BLOCKED'
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
    ),
  );
  Widget filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Heading('Bộ sưu tập công khai', size: 24),
      const SizedBox(height: 8),
      const BodyText(
        'Kiểm tra nội dung đã được chia sẻ công khai hoặc được báo cáo. Không truy cập từ riêng, ghi chú hay tiến độ cá nhân.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: 'Tìm theo tên bộ',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Tìm bộ công khai',
            onPressed: acting
                ? null
                : () {
                    query = search.text.trim();
                    load(nextPage: 1);
                  },
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
        onSubmitted: (value) {
          query = value.trim();
          load(nextPage: 1);
        },
      ),
      const SizedBox(height: 12),
      AdminSelectField(
        label: 'Trạng thái kiểm duyệt',
        value: status,
        options: {
          'ALL': 'Tất cả',
          ...moderationLabels,
          'REPORTED': 'Có báo cáo chưa xử lý',
          'REVIEW_REQUESTED': 'Chờ kiểm tra lại',
        },
        onChanged: acting
            ? null
            : (value) {
                setState(() => status = value);
                load(nextPage: 1);
              },
      ),
      const SizedBox(height: 20),
    ],
  );
  Widget collectionHeader() {
    if (collection == null) return const SizedBox.shrink();
    final row = collection!, state = '${row['moderationState'] ?? 'CLEAR'}';
    final canWrite = context.watch<AuthProvider>().can('collections:moderate');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ('${row['avatarImage'] ?? ''}'.isNotEmpty) ...[
          Center(
            child: SignPhoto(
              row['avatarImage'] as String?,
              word: 'Ảnh đại diện bộ ${row['name']}',
              width: 80,
              height: 80,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Heading('${row['name']}', size: 23),
        const SizedBox(height: 8),
        stateLabel(row),
        if ('${row['description'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          BodyText('${row['description']}'),
        ],
        const SizedBox(height: 12),
        Text('Bản công khai · ${moderationDate(row['capturedAt'])}'),
        const SizedBox(height: 8),
        Text(
          row['discoveryRequested'] == true
              ? 'Chủ bộ đang yêu cầu xuất hiện trong khám phá.'
              : 'Chủ bộ đã rút khỏi khám phá. Khôi phục không tự đăng lại bộ.',
        ),
        if ('${row['moderationReason'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 12),
          Notice('Lý do xử lý: ${row['moderationReason']}'),
        ],
        if (row['reviewRequestedAt'] != null) ...[
          const SizedBox(height: 12),
          const Notice('Chủ bộ đã gửi nội dung mới để kiểm tra.'),
        ],
        if (canWrite) ...[
          const SizedBox(height: 16),
          if (state != 'HIDDEN')
            CollectionAction(
              'Ẩn khỏi khám phá',
              outlined: true,
              icon: Icons.visibility_off_outlined,
              onPressed: acting || loading ? null : () => changeState('HIDDEN'),
            ),
          if (state != 'HIDDEN') const SizedBox(height: 12),
          if (state != 'BLOCKED')
            CollectionAction(
              'Chặn chia sẻ',
              outlined: true,
              danger: true,
              icon: Icons.block,
              onPressed: acting || loading
                  ? null
                  : () => changeState('BLOCKED'),
            ),
          if (state != 'BLOCKED') const SizedBox(height: 12),
          if (state != 'CLEAR')
            CollectionAction(
              'Khôi phục quyền chia sẻ',
              outlined: true,
              icon: Icons.restore,
              onPressed: acting || loading ? null : () => changeState('CLEAR'),
            ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              ChoiceChip(
                label: Text(['Nội dung', 'Báo cáo', 'Lịch sử'][i]),
                selected: panel == i,
                onSelected: acting ? null : (_) => choosePanel(i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (panel == 1) ...[
          AdminSelectField(
            label: 'Trạng thái báo cáo',
            value: reportStatus,
            options: {'ALL': 'Tất cả', ...reportStatusLabels},
            onChanged: acting
                ? null
                : (value) {
                    setState(() => reportStatus = value);
                    load(nextPage: 1);
                  },
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget card(AdminRecord row) {
    if (!detail) {
      return AppCard(
        onTap: acting
            ? null
            : () async {
                await pushAppRoute(context, '/admin/collections/${row['_id']}');
                if (mounted) await load();
              },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SignPhoto(
                row['avatarImage'] as String?,
                width: 56,
                height: 64,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Heading('${row['name']}', size: 18),
                  const SizedBox(height: 6),
                  stateLabel(row),
                  const SizedBox(height: 6),
                  Text(
                    '${row['wordCount']} từ thư viện · ${row['openReports']} báo cáo mở',
                  ),
                  if (row['reviewRequestedAt'] != null)
                    const Text('Có yêu cầu kiểm tra lại'),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }
    if (panel == 0) {
      return AppCard(
        child: ExpansionTile(
          key: PageStorageKey('moderation-${widget.id}-${row['_id']}'),
          tilePadding: EdgeInsets.zero,
          title: Text('${row['word']}'),
          onExpansionChanged: (open) => setState(() {
            if (open) {
              opened.add('${row['_id']}');
            } else {
              opened.remove('${row['_id']}');
            }
          }),
          children: [
            if (opened.contains('${row['_id']}'))
              LearningWordContent(row, quizControls: true),
          ],
        ),
      );
    }
    if (panel == 1) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(
              reportCategoryLabels['${row['category']}'] ?? 'Báo cáo nội dung',
              size: 18,
            ),
            const SizedBox(height: 8),
            Text(reportStatusLabels['${row['status']}'] ?? '${row['status']}'),
            const SizedBox(height: 8),
            Text(moderationDate(row['createdAt'])),
            if ('${row['details'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 12),
              BodyText('${row['details']}'),
            ],
            if ('${row['resolution'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Kết quả: ${row['resolution']}'),
            ],
            if (row['status'] == 'OPEN' &&
                context.watch<AuthProvider>().can('collections:moderate')) ...[
              const SizedBox(height: 16),
              CollectionAction(
                'Đánh dấu đã xử lý',
                outlined: true,
                icon: Icons.task_alt,
                onPressed: acting || loading
                    ? null
                    : () => resolve(row, 'RESOLVED'),
              ),
              const SizedBox(height: 12),
              CollectionAction(
                'Không ghi nhận vi phạm',
                outlined: true,
                icon: Icons.rule,
                onPressed: acting || loading
                    ? null
                    : () => resolve(row, 'DISMISSED'),
              ),
            ],
          ],
        ),
      );
    }
    final action = '${row['action']}';
    final title = action == 'COLLECTION_MODERATION'
        ? '${moderationLabels['${row['from']}']} → ${moderationLabels['${row['to']}']}'
        : action == 'COLLECTION_REPORT_RESOLVE'
        ? 'Xử lý báo cáo: ${reportStatusLabels['${row['to']}']}'
        : 'Chủ bộ gửi lại để kiểm tra';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Heading(title, size: 17),
          const SizedBox(height: 8),
          Text('${row['actorName']} · ${row['actorRole']}'),
          const SizedBox(height: 8),
          Text(moderationDate(row['createdAt'])),
          const SizedBox(height: 12),
          BodyText('${row['reason'] ?? ''}'),
        ],
      ),
    );
  }

  Widget footer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (error != null) ...[
        Notice(error!),
        const SizedBox(height: 12),
        CollectionAction(
          'Thử tải lại',
          outlined: true,
          icon: Icons.refresh,
          onPressed: acting ? null : () => load(),
        ),
      ],
      if (!loading && error == null && items.isEmpty)
        EmptyView(
          title: !detail
              ? 'Không có bộ phù hợp'
              : panel == 1
              ? 'Chưa có báo cáo phù hợp'
              : panel == 2
              ? 'Chưa có thao tác kiểm duyệt'
              : 'Chưa có từ thư viện khả dụng',
          description: !detail
              ? 'Thử đổi từ khóa hoặc trạng thái. Bộ riêng không được liệt kê ở đây.'
              : panel == 0
              ? 'Từ có thể đã được gỡ khỏi thư viện.'
              : 'Dữ liệu sẽ xuất hiện khi có thao tác tương ứng.',
          icon: Icons.fact_check_outlined,
        ),
      if (pages > 1)
        LearningPager(
          page: page,
          pages: pages,
          onPage: (value) {
            if (!acting && !loading) load(nextPage: value);
          },
        ),
      if (!loading && total > 0)
        Text('$total mục · Trang $page/$pages', textAlign: TextAlign.center),
    ],
  );
  @override
  Widget build(BuildContext context) => AppPage(
    title: detail ? 'Kiểm duyệt bộ' : 'Bộ sưu tập công khai',
    scroll: false,
    padding: EdgeInsets.zero,
    actions: [
      IconButton(
        tooltip: 'Làm mới kiểm duyệt',
        onPressed: loading || acting ? null : () => load(),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: RefreshIndicator(
      onRefresh: () async {
        if (!acting) await load();
      },
      child: ListView.builder(
        key: PageStorageKey('moderation-${widget.id ?? 'list'}-$panel'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        itemCount: items.length + 2,
        itemBuilder: (context, index) => index == 0
            ? (detail ? collectionHeader() : filters())
            : index == items.length + 1
            ? footer()
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card(items[index - 1]),
              ),
      ),
    ),
  );
}

class _ModerationReasonDialog extends StatefulWidget {
  const _ModerationReasonDialog({
    required this.title,
    required this.explanation,
    required this.submitLabel,
    required this.onSave,
    this.danger = false,
  });
  final String title, explanation, submitLabel;
  final bool danger;
  final Future<void> Function(String) onSave;
  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  final reason = TextEditingController(), form = GlobalKey<FormState>();
  bool busy = false, stale = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || stale || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = collectionError(e);
          stale = e is ApiException && e.statusCode == 409;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BodyText(widget.explanation),
              const SizedBox(height: 16),
              TextFormField(
                controller: reason,
                readOnly: busy,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Lý do / kết quả xử lý',
                  hintText: 'Nhập ít nhất 5 ký tự',
                ),
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Nhập lý do rõ ràng, ít nhất 5 ký tự.'
                    : null,
              ),
              if (error != null) Notice(error!),
              const SizedBox(height: 16),
              CollectionAction(
                widget.submitLabel,
                danger: widget.danger,
                busy: busy,
                onPressed: busy || stale ? null : save,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: Text(stale ? 'Đóng để tải lại' : 'Hủy'),
        ),
      ],
    ),
  );
}
