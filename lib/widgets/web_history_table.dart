import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import 'ui.dart';

/// Sorting is explicitly scoped to the server page, never a partial global sort.
class WebHistoryTable extends StatefulWidget {
  const WebHistoryTable({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    this.total,
  });
  final List<Conversation> items;
  final int? total;
  final ValueChanged<Conversation> onOpen, onFavorite, onDelete;
  @override
  State<WebHistoryTable> createState() => _WebHistoryTableState();
}

class _WebHistoryTableState extends State<WebHistoryTable> {
  int column = 2;
  bool ascending = false;
  late final source = _ConversationRows();
  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    source.items = [...widget.items]
      ..sort((a, b) {
        final order = switch (column) {
          0 => a.content.compareTo(b.content),
          1 => a.label.compareTo(b.label),
          _ => a.createdAt.compareTo(b.createdAt),
        };
        return ascending ? order : -order;
      });
    source.open = widget.onOpen;
    source.favorite = widget.onFavorite;
    source.delete = widget.onDelete;
    source.refresh();
    DataColumn sortable(String label, int index) => DataColumn(
      label: Text(label),
      onSort: (c, asc) => setState(() {
        column = c;
        ascending = asc;
      }),
    );
    source.danger = Theme.of(context).colorScheme.error;
    source.rowHighlight = Theme.of(context).colorScheme.primary.withAlpha(24);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Heading(
                  '${widget.total ?? widget.items.length} hội thoại',
                  size: 20,
                ),
                const BodyText('Sắp xếp áp dụng cho trang hiện tại'),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              source.contentWidth = (constraints.maxWidth * .36).clamp(
                220.0,
                600.0,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    sortColumnIndex: column,
                    sortAscending: ascending,
                    columnSpacing: 24,
                    horizontalMargin: 20,
                    dataRowMinHeight: 64,
                    dataRowMaxHeight: 88,
                    columns: [
                      sortable('Nội dung', 0),
                      sortable('Loại hội thoại', 1),
                      sortable('Thời gian', 2),
                      const DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (var i = 0; i < source.items.length; i++)
                        source.getRow(i)!,
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConversationRows extends DataTableSource {
  void refresh() => notifyListeners();
  List<Conversation> items = [];
  Color danger = Colors.red, rowHighlight = Colors.transparent;
  double contentWidth = 240;
  late ValueChanged<Conversation> open, favorite, delete;
  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final item = items[index];
    final icon = switch (item.direction) {
      ConversationDirection.signToSpeech => Icons.back_hand_outlined,
      ConversationDirection.speechToText => Icons.mic_none,
      _ => Icons.text_fields,
    };
    return DataRow.byIndex(
      index: index,
      color: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? rowHighlight
            : null,
      ),
      onSelectChanged: (_) => open(item),
      cells: [
        DataCell(
          SizedBox(
            width: contentWidth,
            child: Text(
              item.content.trim().runes.length < 4
                  ? 'Hội thoại ngắn: ${item.content}'
                  : item.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(item.label),
            ],
          ),
        ),
        DataCell(
          Text(DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt.toLocal())),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Mở hội thoại',
                onPressed: () => open(item),
                icon: const Icon(Icons.open_in_new),
              ),
              IconButton(
                tooltip: item.favorite ? 'Bỏ yêu thích' : 'Yêu thích',
                onPressed: () => favorite(item),
                icon: Icon(
                  item.favorite ? Icons.favorite : Icons.favorite_border,
                ),
              ),
              IconButton(
                tooltip: 'Xóa hội thoại',
                color: danger,
                onPressed: () => delete(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  int get rowCount => items.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}
