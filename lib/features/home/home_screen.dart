import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final name = state.guest ? 'Khách' : state.name;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Chào buổi sáng,'
        : hour < 18
        ? 'Chào buổi chiều,'
        : 'Chào buổi tối,';
    return AppPage(
      title: 'SignVoice',
      showBack: false,
      tabIndex: 0,
      actions: [
        IconButton(
          tooltip: 'Thông báo',
          icon: const Icon(Icons.notifications_none),
          onPressed: () => toast(context, 'Bạn chưa có thông báo mới.'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: InkWell(
            onTap: () => openRoot(context, 'S25'),
            borderRadius: BorderRadius.circular(30),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.blue,
              child: Text(
                name.isEmpty ? 'S' : name[0],
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BodyText(greeting),
          const SizedBox(height: 4),
          Heading('$name 👋', size: 24),
          const SizedBox(height: 24),
          const Heading('Hôm nay bạn muốn giao tiếp\nnhư thế nào?', size: 18),
          const SizedBox(height: 16),
          _FeatureCard(
            title: 'Ký hiệu → Giọng nói',
            description: 'Chuyển ký hiệu tay thành văn bản và lời nói.',
            label: 'Bắt đầu nhận diện',
            color: AppColors.blue,
            icon: Icons.back_hand_outlined,
            onTap: () => openScreen(context, 'S10'),
          ),
          const SizedBox(height: 14),
          _FeatureCard(
            title: 'Giọng nói → Văn bản',
            description: 'Chuyển lời nói thành chữ lớn, dễ đọc.',
            label: 'Bắt đầu ghi âm',
            color: AppColors.teal,
            icon: Icons.mic_none,
            onTap: () => openScreen(context, 'S15'),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Khám phá từ điển', () => openRoot(context, 'S22')),
          const SizedBox(height: 10),
          SizedBox(
            height: 114,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(
                width: 84,
                child: AppCard(
                  padding: const EdgeInsets.all(10),
                  onTap: () {
                    state.selectSign(signs[i]);
                    openScreen(context, 'S23');
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.back_hand_outlined,
                        color: AppColors.blue,
                        size: 30,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        signs[i].name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SectionTitle('Lịch sử gần đây', () => openRoot(context, 'S20')),
          const SizedBox(height: 10),
          if (state.history.isEmpty)
            const AppCard(
              child: EmptyView(
                title: 'Chưa có lịch sử hội thoại',
                description: 'Lưu kết quả phiên dịch để xem lại tại đây.',
              ),
            ),
          for (final item in state.history.take(2)) ...[
            AppCard(
              onTap: () {
                state.selectConversation(item);
                openScreen(context, 'S21');
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SignVoiceBadge(
                    item.label,
                    color: item.direction == ConversationDirection.signToSpeech
                        ? AppColors.blue
                        : AppColors.teal,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.content,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  BodyText(item.time),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.onTap);
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Heading(title, size: 17)),
      TextButton(onPressed: onTap, child: const Text('Xem tất cả')),
    ],
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.description,
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final String title, description, label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        colors: [color, Color.lerp(color, Colors.black, .18)!],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: 0,
          top: 0,
          child: Icon(icon, size: 72, color: Colors.white.withAlpha(40)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '$label →',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
