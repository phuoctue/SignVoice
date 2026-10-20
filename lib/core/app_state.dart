import 'package:flutter/material.dart';

enum ConversationDirection { signToSpeech, speechToText }

class Conversation {
  Conversation({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.direction,
    this.favorite = false,
  });
  final String id;
  final String content;
  final DateTime createdAt;
  final ConversationDirection direction;
  bool favorite;

  String get label => direction == ConversationDirection.signToSpeech
      ? 'Ký hiệu → Giọng nói'
      : 'Giọng nói → Văn bản';
  String get time {
    final now = DateTime.now();
    if (now.difference(createdAt).inSeconds < 60) return 'Vừa xong';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(createdAt.hour)}:${two(createdAt.minute)} • '
        '${two(createdAt.day)}/${two(createdAt.month)}';
  }
}

class SignEntry {
  const SignEntry(
    this.name,
    this.category,
    this.meaning,
    this.example, {
    this.instructions,
    this.id,
    this.videoUrl,
  });
  final String name, category, meaning, example;
  final String? instructions;
  final String? id, videoUrl;
  String get favoriteKey => id ?? name;
}

// Các mục demo lấy từ source Figma. Media VSL cần bổ sung khi có bộ dữ liệu.
const signs = <SignEntry>[
  SignEntry(
    'Xin chào',
    'Chào hỏi',
    'Dùng để chào hỏi khi gặp mặt hoặc bắt đầu cuộc trò chuyện.',
    'Xin chào, tôi tên là Minh.',
    instructions:
        'Đưa bàn tay phải lên ngang mặt, lòng bàn tay hướng ra ngoài, '
        'vẫy nhẹ sang trái rồi sang phải 1–2 lần.',
  ),
  SignEntry(
    'Cảm ơn',
    'Chào hỏi',
    'Bày tỏ sự biết ơn.',
    'Cảm ơn bạn đã giúp tôi.',
  ),
  SignEntry(
    'Xin lỗi',
    'Chào hỏi',
    'Bày tỏ lời xin lỗi.',
    'Xin lỗi, tôi đến muộn.',
  ),
  SignEntry('Giúp đỡ', 'Khẩn cấp', 'Đề nghị được hỗ trợ.', 'Tôi cần giúp đỡ.'),
  SignEntry('Ăn', 'Ăn uống', 'Nói về hoạt động ăn.', 'Tôi muốn ăn.'),
  SignEntry('Uống', 'Ăn uống', 'Nói về hoạt động uống.', 'Tôi muốn uống nước.'),
  SignEntry('Đau', 'Sức khỏe', 'Diễn tả cảm giác đau.', 'Tôi bị đau.'),
  SignEntry(
    'Tạm biệt',
    'Chào hỏi',
    'Chào khi kết thúc cuộc gặp.',
    'Tạm biệt, hẹn gặp lại.',
  ),
  SignEntry('Vui', 'Cảm xúc', 'Diễn tả cảm xúc vui.', 'Tôi rất vui.'),
  SignEntry('Buồn', 'Cảm xúc', 'Diễn tả cảm xúc buồn.', 'Tôi đang buồn.'),
];

class AppState extends ChangeNotifier {
  String? _accountId;
  bool guest = false;
  String name = 'Nguyễn Minh Tuấn';
  String email = 'minhtuan@email.com';
  final List<String> sentence = [];
  final Set<String> favorites = {'Xin chào', 'Cảm ơn'};
  final List<Conversation> history = [
    Conversation(
      id: 'h1',
      content: 'Xin chào, tôi cần giúp đỡ.',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      direction: ConversationDirection.signToSpeech,
    ),
    Conversation(
      id: 'h2',
      content: 'Bạn muốn đến đâu?',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      direction: ConversationDirection.speechToText,
      favorite: true,
    ),
    Conversation(
      id: 'h3',
      content: 'Tôi muốn uống nước.',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      direction: ConversationDirection.signToSpeech,
    ),
  ];
  String detectedSign = 'Xin chào';
  String transcript = '';
  String? selectedHistoryId;
  SignEntry selectedSign = signs.first;
  ThemeMode themeMode = ThemeMode.light;
  double fontScale = 1, speechSpeed = 1, speechPitch = 1;
  bool highContrast = false, autoSpeak = false;
  bool cameraAllowed = false, microphoneAllowed = false;
  bool permissionCamera = true;
  bool online = true, syncing = false;
  DateTime? lastSync;
  int avatarColor = 0;

  void update(VoidCallback action) {
    action();
    notifyListeners();
  }

  void enter({required bool asGuest, String? displayName, String? userEmail}) {
    guest = asGuest;
    if (displayName != null) name = displayName;
    if (userEmail != null) email = userEmail;
    notifyListeners();
  }

  void bindAccount(
    String accountId, {
    required bool asGuest,
    String? displayName,
    String? userEmail,
  }) {
    if (_accountId != accountId) {
      history.clear();
      favorites.clear();
      sentence.clear();
      selectedHistoryId = null;
      _accountId = accountId;
    }
    guest = asGuest;
    if (displayName != null) name = displayName;
    if (userEmail != null) email = userEmail;
    notifyListeners();
  }

  void addWord(String word) => update(() => sentence.add(word));
  String get sentenceText => sentence.isEmpty ? '' : '${sentence.join(', ')}.';
  void toggleSign(String word) => update(() {
    if (!favorites.add(word)) favorites.remove(word);
  });
  void selectSign(SignEntry entry) => update(() => selectedSign = entry);
  void selectConversation(Conversation entry) =>
      update(() => selectedHistoryId = entry.id);
  Conversation? get selectedConversation {
    for (final entry in history) {
      if (entry.id == selectedHistoryId) return entry;
    }
    return history.isEmpty ? null : history.first;
  }

  void toggleConversation(Conversation entry) =>
      update(() => entry.favorite = !entry.favorite);
  void saveConversation(String text, ConversationDirection direction) {
    if (text.trim().isEmpty) return;
    update(() {
      final now = DateTime.now();
      final entry = Conversation(
        id: now.microsecondsSinceEpoch.toString(),
        content: text.trim(),
        createdAt: now,
        direction: direction,
      );
      history.insert(0, entry);
      selectedHistoryId = entry.id;
    });
  }

  void removeConversation(String id) =>
      update(() => history.removeWhere((h) => h.id == id));
  void clearLocalData() => update(() {
    history.clear();
    favorites.clear();
    sentence.clear();
    selectedHistoryId = null;
  });
  Future<void> simulateSync() async {
    if (syncing || !online || guest) return;
    update(() => syncing = true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    update(() {
      syncing = false;
      lastSync = DateTime.now();
    });
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
