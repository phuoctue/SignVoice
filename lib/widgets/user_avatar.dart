import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api/api_config.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.color,
    this.radius = 42,
    this.preview,
  });
  final String name, url;
  final Color color;
  final double radius;
  final Uint8List? preview;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Ảnh đại diện ${name.trim()}',
    image: true,
    child: CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: preview != null
          ? MemoryImage(preview!)
          : url.isEmpty
          ? null
          : NetworkImage(ApiConfig.avatarMediaUrl(url)),
      onForegroundImageError: preview == null && url.isEmpty ? null : (_, _) {},
      child: Text(
        name.isEmpty ? 'S' : name.characters.first,
        style: TextStyle(
          fontSize: radius * .7,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
