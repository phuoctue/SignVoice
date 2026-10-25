import 'package:flutter/material.dart';

import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';

class LearningAnalysisCard extends StatelessWidget {
  const LearningAnalysisCard({super.key, required this.result});
  final LearningRecord result;

  @override
  Widget build(BuildContext context) {
    final summary = result['summary'] as Map? ?? {};
    int count(String key) => (summary[key] as num? ?? 0).toInt();
    final percent = count('rememberedPercent');
    final topics = (result['topics'] as List? ?? []).cast<Map>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SignVoiceBadge(
            result['source'] == 'lm-studio'
                ? 'Phân tích từ LM Studio'
                : 'Phân tích từ số liệu',
          ),
          const SizedBox(height: 12),
          Text(
            'Đã nhớ ${count('remembered')} / ${count('total')} từ ($percent%)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (percent / 100).clamp(0.0, 1.0)),
          const SizedBox(height: 8),
          BodyText('${count('topicCount')} chủ đề đã bắt đầu'),
          const SizedBox(height: 12),
          BodyText('${result['analysis'] ?? ''}'),
          if (result['source'] == 'rules') ...[
            const SizedBox(height: 12),
            const BodyText(
              'AI chưa sẵn sàng. Phần phân tích trên được tính từ tiến độ đã lưu.',
            ),
          ],
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Chủ đề cần chú ý',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final topic in topics.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BodyText(
                  '${topic['name']}: đã nhớ ${topic['remembered']}/${topic['total']} từ (${topic['rememberedPercent']}%), cần ôn ${topic['review']} từ.',
                ),
              ),
          ],
          const SizedBox(height: 12),
          const BodyText(
            'Số liệu tại thời điểm phân tích, theo tiến độ đã ghi nhận.',
          ),
        ],
      ),
    );
  }
}
