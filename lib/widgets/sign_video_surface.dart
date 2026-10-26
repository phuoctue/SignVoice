import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SignVideoSurface extends StatelessWidget {
  const SignVideoSurface(this.controller, {super.key});
  final VideoPlayerController controller;
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      VideoPlayer(controller),
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (_, value, _) {
          if (value.hasError) {
            return const ColoredBox(
              color: Colors.black54,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Video bị gián đoạn. Hãy thử tải lại.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
          }
          if (!value.isBuffering) return const SizedBox.shrink();
          return Semantics(
            label: 'Đang tải video',
            child: const CircularProgressIndicator(),
          );
        },
      ),
    ],
  );
}
