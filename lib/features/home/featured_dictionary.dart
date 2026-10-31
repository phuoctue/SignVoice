import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin/admin_workspace_service.dart';
import '../../widgets/ui.dart';
import '../learning/learning_widgets.dart';
import '../../services/media/managed_media.dart';

class FeaturedDictionary extends StatefulWidget {
  const FeaturedDictionary({super.key});
  @override
  State<FeaturedDictionary> createState() => _FeaturedDictionaryState();
}

class _FeaturedDictionaryState extends State<FeaturedDictionary> {
  List<AdminRecord>? entries;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context
          .read<AdminWorkspaceService>()
          .featuredEntries();
      primeImagePreviews(result);
      if (mounted) setState(() => entries = result);
    } catch (_) {
      if (mounted) setState(() => error = 'Chưa tải được từ điển.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    if (error != null) {
      return Row(
        children: [
          Expanded(child: BodyText(error!)),
          TextButton(onPressed: load, child: const Text('Thử lại')),
        ],
      );
    }
    if (entries!.isEmpty) {
      return const BodyText('Chưa có ký hiệu được xuất bản.');
    }
    final labelHeight = MediaQuery.textScalerOf(context).scale(14) * 3;
    Widget tile(AdminRecord item, double width) => SizedBox(
      width: width,
      height: 134 + labelHeight,
      child: AppCard(
        padding: const EdgeInsets.all(10),
        onTap: () => pushAppRoute(
          context,
          '/dictionary/${Uri.encodeComponent('${item['_id']}')}',
        ),
        child: Column(
          children: [
            SignPhoto(
              item['thumbnailUrl'] as String?,
              word: '${item['word']}',
              width: (width - 20).clamp(0.0, 160.0),
              height: 100,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Text(
                  '${item['word']}',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (isDesktopLayout(context)) {
          final columns = constraints.maxWidth >= 1000 ? 6 : 3;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final item in entries!.take(6)) tile(item, width)],
          );
        }
        return SizedBox(
          height: 134 + labelHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries!.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => tile(entries![i], 148),
          ),
        );
      },
    );
  }
}
