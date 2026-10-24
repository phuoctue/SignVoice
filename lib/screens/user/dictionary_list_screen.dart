import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dictionary_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/favorites_provider.dart';

/// Dictionary list screen with search and filters
class DictionaryListScreen extends StatefulWidget {
  const DictionaryListScreen({super.key});

  @override
  State<DictionaryListScreen> createState() => _DictionaryListScreenState();
}

class _DictionaryListScreenState extends State<DictionaryListScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedCategory;
  String? _selectedDifficulty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DictionaryProvider>().loadEntries(reset: true);
      context.read<CategoryProvider>().loadCategories();
      context.read<FavoritesProvider>().loadFavorites();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      context.read<DictionaryProvider>().loadMore(
        categoryId: _selectedCategory,
        difficulty: _selectedDifficulty,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryProvider = context.watch<DictionaryProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final favoritesProvider = context.watch<FavoritesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Từ điển'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, '/dictionary/search'),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          if (categoryProvider.categories.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  _CategoryChip(
                    label: 'Tất cả',
                    isSelected: _selectedCategory == null,
                    onTap: () {
                      setState(() => _selectedCategory = null);
                      dictionaryProvider.loadEntries(reset: true);
                    },
                  ),
                  const SizedBox(width: 8),
                  ...categoryProvider.categories.map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryChip(
                        label: category.name,
                        isSelected: _selectedCategory == category.id,
                        onTap: () {
                          setState(() => _selectedCategory = category.id);
                          dictionaryProvider.loadEntries(
                            categoryId: category.id,
                            reset: true,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Entry list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => dictionaryProvider.loadEntries(
                categoryId: _selectedCategory,
                difficulty: _selectedDifficulty,
                reset: true,
              ),
              child: dictionaryProvider.errorMessage != null
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
                            onPressed: () =>
                                dictionaryProvider.loadEntries(reset: true),
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : dictionaryProvider.entries.isEmpty &&
                        !dictionaryProvider.isLoading
                  ? const Center(child: Text('Chưa có dữ liệu'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          dictionaryProvider.entries.length +
                          (dictionaryProvider.isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= dictionaryProvider.entries.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final entry = dictionaryProvider.entries[index];
                        final isFavorite = favoritesProvider.isFavorite(
                          entry.id,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(entry.word),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.definition,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                if (entry.difficulty != null)
                                  Chip(
                                    label: Text(
                                      entry.difficultyLabel ?? '',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFavorite ? Colors.red : null,
                                  ),
                                  onPressed: () => favoritesProvider
                                      .toggleFavorite(entry.id),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 16),
                              ],
                            ),
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/dictionary/${entry.id}',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    final provider = context.read<DictionaryProvider>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lọc theo độ khó'),
        content: RadioGroup<String?>(
          groupValue: _selectedDifficulty,
          onChanged: (value) {
            setState(() => _selectedDifficulty = value);
            Navigator.pop(dialogContext);
            provider.loadEntries(
              categoryId: _selectedCategory,
              difficulty: value,
              reset: true,
            );
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String?>(title: Text('Tất cả'), value: null),
              RadioListTile<String?>(title: Text('Dễ'), value: 'BEGINNER'),
              RadioListTile<String?>(
                title: Text('Trung bình'),
                value: 'INTERMEDIATE',
              ),
              RadioListTile<String?>(title: Text('Khó'), value: 'ADVANCED'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
    );
  }
}
