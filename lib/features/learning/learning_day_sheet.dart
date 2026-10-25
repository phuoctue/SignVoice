import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

class LearningDaySheet extends StatefulWidget {
  const LearningDaySheet({
    super.key,
    required this.date,
    required this.service,
    this.initialKind = 'learned',
  });
  final String date, initialKind;
  final LearningService service;
  @override
  State<LearningDaySheet> createState() => _LearningDaySheetState();
}

class _LearningDaySheetState extends State<LearningDaySheet> {
  late String kind = widget.initialKind;
  int page = 1, request = 0;
  bool loading = true;
  String? error;
  LearningPage? data;
  late final AuthProvider auth;
  late final int ownerEpoch;
  bool get sameOwner => auth.isAuthenticated && auth.accountEpoch == ownerEpoch;
  @override
  void initState() {
    super.initState();
    auth = context.read<AuthProvider>();
    ownerEpoch = auth.accountEpoch;
    auth.addListener(checkOwner);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    auth.removeListener(checkOwner);
    request++;
    super.dispose();
  }

  void checkOwner() {
    if (!sameOwner && mounted) {
      request++;
      setState(() => data = null);
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route != null) Navigator.of(context).removeRoute(route);
      });
    }
  }

  Future<void> load() async {
    if (!sameOwner) return;
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.service.activity(
        date: widget.date,
        kind: kind,
        page: page,
      );
      if (!mounted || !sameOwner || current != request) return;
      if (page > result.pages) {
        page = result.pages;
        await load();
        return;
      }
      setState(() => data = result);
    } catch (e) {
      if (mounted && current == request) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa tải được danh sách từ. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  String time(Object? value) {
    final date = DateTime.tryParse('$value')
        ?.toUtc()
        .add(const Duration(hours: 7));
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => !sameOwner
      ? const SizedBox.shrink()
      : SizedBox(
          height: MediaQuery.sizeOf(context).height * .88,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                'Ngày ${widget.date.split('-').reversed.join('/')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: IconButton(
                tooltip: 'Đóng',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BodyText(
                    'Danh sách từ thực tế đã ghi nhận trong ngày, theo giờ Việt Nam.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in {
                        'learned': 'Đã học',
                        'reviewed': 'Đã ôn',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: kind == entry.key,
                          onSelected: (_) {
                            if (kind != entry.key) {
                              kind = entry.key;
                              page = 1;
                              load();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null) ...[
                    Notice(error!),
                    TextButton(onPressed: load, child: const Text('Thử lại')),
                  ],
                  if (!loading && error == null && data != null) ...[
                    Text(
                      '${data!.total} từ ${kind == 'learned' ? 'đã học' : 'đã ôn'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (data!.items.isEmpty)
                      EmptyView(
                        title:
                            'Chưa có từ ${kind == 'learned' ? 'đã học' : 'đã ôn'} trong ngày này',
                        description:
                            'Chỉ các lượt được ghi nhận mới xuất hiện ở đây.',
                        icon: Icons.event_note_rounded,
                      ),
                    for (final word in data!.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Heading('${word['word'] ?? ''}', size: 19),
                              BodyText('${word['topicName'] ?? ''}'),
                              const SizedBox(height: 8),
                              if (kind == 'learned')
                                SignVoiceBadge(
                                  word['isNew'] == true
                                      ? 'Từ mới'
                                      : learningLabels[word['stage']] ??
                                            'Đã ghi nhận học',
                                )
                              else
                                SignVoiceBadge(
                                  word['matched'] == true
                                      ? 'Lần gần nhất: đã khớp'
                                      : 'Lần gần nhất: chưa khớp',
                                  color: word['matched'] == true
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFB45309),
                                ),
                              const SizedBox(height: 8),
                              BodyText(
                                'Ghi nhận gần nhất lúc ${time(word['occurredAt'])}',
                              ),
                              if (kind == 'reviewed' &&
                                  (word['attempts'] as num? ?? 0) > 1)
                                BodyText(
                                  '${word['attempts']} lượt quiz trong ngày, tính 1 từ ôn.',
                                ),
                              if (RegExp(
                                r'^[a-f0-9]{24}$',
                                caseSensitive: false,
                              ).hasMatch('${word['entryId']}'))
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.pushNamed(
                                      context,
                                      '/learn/history?entryId=${word['entryId']}',
                                    );
                                    if (mounted) await load();
                                  },
                                  child: const Text('Lịch sử từ'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (data!.pages > 1)
                      LearningPager(
                        page: page,
                        pages: data!.pages,
                        onPage: (value) {
                          page = value;
                          load();
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
}
