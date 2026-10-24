import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../models/dictionary_entry_model.dart';

/// Dictionary entry detail screen
class DictionaryDetailScreen extends StatefulWidget {
  final String entryId;

  const DictionaryDetailScreen({
    super.key,
    required this.entryId,
  });

  @override
  State<DictionaryDetailScreen> createState() => _DictionaryDetailScreenState();
}

class _DictionaryDetailScreenState extends State<DictionaryDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DictionaryProvider>().loadEntryById(widget.entryId);
      context.read<FavoritesProvider>().loadFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryProvider = context.watch<DictionaryProvider>();
    final favoritesProvider = context.watch<FavoritesProvider>();
    final entry = dictionaryProvider.selectedEntry;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết'),
        actions: [
          if (entry != null)
            IconButton(
              icon: Icon(
                favoritesProvider.isFavorite(entry.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: favoritesProvider.isFavorite(entry.id)
                    ? Colors.red
                    : null,
              ),
              onPressed: () => favoritesProvider.toggleFavorite(entry.id),
            ),
        ],
      ),
      body: dictionaryProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : dictionaryProvider.errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Lỗi: ${dictionaryProvider.errorMessage}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => dictionaryProvider.loadEntryById(
                          widget.entryId,
                        ),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : entry == null
                  ? const Center(child: Text('Không tìm thấy dữ liệu'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Word
                          Text(
                            entry.word,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),

                          // Difficulty badge
                          if (entry.difficulty != null)
                            Chip(
                              label: Text(entry.difficultyLabel ?? ''),
                              backgroundColor: _getDifficultyColor(
                                entry.difficulty!,
                              ),
                            ),
                          const SizedBox(height: 16),

                          // Definition
                          Text(
                            'Định nghĩa',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(entry.definition),
                          const SizedBox(height: 24),

                          // Video
                          Text(
                            'Video minh họa',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (entry.videoUrl.isNotEmpty)
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.play_circle_outline,
                                        size: 48),
                                    const SizedBox(height: 8),
                                    Text('Video: ${entry.videoUrl}'),
                                  ],
                                ),
                              ),
                            )
                          else
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text('Video chưa có'),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Usage example
                          if (entry.usageExample != null && entry.usageExample!.isNotEmpty) ...[
                            Text(
                              'Ví dụ sử dụng',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(entry.usageExample!),
                            const SizedBox(height: 24),
                          ],

                          // Tags
                          if (entry.tags != null && entry.tags!.isNotEmpty) ...[
                            Text(
                              'Thẻ',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: entry.tags!
                                  .map((tag) => Chip(label: Text(tag)))
                                  .toList(),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Related words
                          if (entry.relatedWords != null && entry.relatedWords!.isNotEmpty) ...[
                            Text(
                              'Từ liên quan',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: entry.relatedWords!
                                  .map((relatedWord) => ActionChip(
                                        label: Text(relatedWord.entryId),
                                        onPressed: () {
                                          // Navigate to related entry
                                          Navigator.pushNamed(
                                            context,
                                            '/dictionary/${relatedWord.entryId}',
                                          );
                                        },
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Color _getDifficultyColor(DifficultyLevel difficulty) {
    switch (difficulty) {
      case DifficultyLevel.beginner:
        return Colors.green[100]!;
      case DifficultyLevel.intermediate:
        return Colors.orange[100]!;
      case DifficultyLevel.advanced:
        return Colors.red[100]!;
    }
  }
}
