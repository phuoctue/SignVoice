import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api/api_config.dart';
import '../services/user/avatar_image_cache.dart';

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.color,
    this.radius = 42,
    this.preview,
    this.accountId,
  });
  final String name, url;
  final Color color;
  final double radius;
  final Uint8List? preview;
  final String? accountId;
  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Future<Uint8List>? _loading;
  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.accountId != widget.accountId) {
      _loading = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserAvatar(:name, :url, :color, :radius, :preview, :accountId) =
        widget;
    Widget avatar(Uint8List? cached, {bool useNetwork = true}) => Semantics(
      label: 'Ảnh đại diện ${name.trim()}',
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color,
        foregroundImage: preview != null || cached != null
            ? MemoryImage((preview ?? cached)!)
            : url.isEmpty || !useNetwork
            ? null
            : NetworkImage(ApiConfig.avatarMediaUrl(url)),
        onForegroundImageError:
            preview == null && cached == null && (url.isEmpty || !useNetwork)
            ? null
            : (_, _) {},
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
    final cached = avatarImages.peek(accountId, url);
    if (preview != null ||
        cached != null ||
        !avatarImages.accepts(accountId, url)) {
      return avatar(cached);
    }
    _loading ??= avatarImages.load(accountId!, url);
    return FutureBuilder<Uint8List>(
      future: _loading,
      builder: (_, snapshot) => avatar(snapshot.data, useNetwork: false),
    );
  }
}
