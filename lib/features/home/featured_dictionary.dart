import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin/admin_workspace_service.dart';
import '../../widgets/ui.dart';
import '../learning/learning_widgets.dart';

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
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 3;
    return SizedBox(
      height: 128 + labelHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries!.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = entries![index];
          final word = '${item['word']}';
          return SizedBox(
            width: 136,
            child: AppCard(
              padding: const EdgeInsets.all(10),
              onTap: () => Navigator.pushNamed(
                context,
                '/dictionary/${Uri.encodeComponent('${item['_id']}')}',
              ),
              child: Column(
                children: [
                  SignPhoto(
                    item['thumbnailUrl'] as String?,
                    word: word,
                    width: 116,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Center(
                      child: Text(
                        word,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
