import 'dart:async';

import 'package:flutter/material.dart';

import '../services/user/user_data_service.dart';
import '../services/api/api_exception.dart';

enum ConversationDirection { signToSpeech, speechToText, text }

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

  String get label => switch (direction) {
    ConversationDirection.signToSpeech => 'Ký hiệu → Giọng nói',
    ConversationDirection.speechToText => 'Giọng nói → Hình ảnh',
    ConversationDirection.text => 'Văn bản',
  };
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
    this.thumbnailUrl,
    this.imageUrls = const [],
  });
  final String name, category, meaning, example;
  final String? instructions;
  final String? id, videoUrl;
  final String? thumbnailUrl;
  final List<String> imageUrls;
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
  int _localConversationSequence = 0;

  /// A service is injected by SignVoiceApp. Omitting it supports isolated widget fixtures.
  AppState({this.service});
  final UserDataService? service;
  String? _accountId;
  int _epoch = 0, _loadEpoch = 0, _revision = 0;
  bool _disposed = false;
  int get accountEpoch => _epoch;
  bool isCurrent(int epoch) =>
      !_disposed && epoch == _epoch && _accountId != null;
  bool get persisted => service != null;
  bool get ready => !persisted || _ready;
  bool _ready = false;
  bool guest = false;
  String name = '', email = '', avatarUrl = '', accountType = 'LOCAL';
  final List<String> sentence = [];
  final Set<String> favorites = {};
  final List<Conversation> history = [];
  String detectedSign = '', transcript = '';
  String? selectedHistoryId;
  SignEntry selectedSign = signs.first;
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1, speechSpeed = 1, speechPitch = 1;
  bool highContrast = false, autoSpeak = false;
  bool cameraAllowed = false,
      microphoneAllowed = false,
      permissionCamera = true;
  bool online = true, syncing = false, saving = false;
  String? error;
  DateTime? lastSync;
  int avatarColor = 0, historyPage = 1, historyPages = 1;
  String historySearch = '';
  String? historyDirection;
  bool? historyFavorite;
  Future<void> _settingsQueue = Future<void>.value();

  void update(VoidCallback action) {
    if (_disposed) return;
    action();
    notifyListeners();
  }

  void enter({required bool asGuest, String? displayName, String? userEmail}) {
    update(() {
      guest = asGuest;
      if (displayName != null) name = displayName;
      if (userEmail != null) email = userEmail;
    });
  }

  void _reset() {
    history.clear();
    favorites.clear();
    sentence.clear();
    selectedHistoryId = null;
    selectedSign = signs.first;
    detectedSign = '';
    transcript = '';
    avatarUrl = '';
    themeMode = ThemeMode.system;
    fontScale = 1;
    speechSpeed = 1;
    speechPitch = 1;
    highContrast = false;
    autoSpeak = false;
    avatarColor = 0;
    cameraAllowed = false;
    microphoneAllowed = false;
    lastSync = null;
    error = null;
    syncing = false;
    saving = false;
    historyPage = 1;
    historyPages = 1;
    historySearch = '';
    historyDirection = null;
    historyFavorite = null;
    _ready = false;
  }

  void bindAccount(
    String accountId, {
    required bool asGuest,
    String? displayName,
    String? userEmail,
  }) {
    final changed = _accountId != accountId;
    if (changed) {
      _epoch++;
      _loadEpoch++;
      _revision++;
      _reset();
      _accountId = accountId;
    }
    guest = asGuest;
    if (displayName != null) name = displayName;
    if (userEmail != null) email = userEmail;
    if (!_disposed) notifyListeners();
    if (changed && persisted) unawaited(synchronize());
  }

  void unbindAccount() {
    _epoch++;
    _loadEpoch++;
    _revision++;
    _accountId = null;
    _reset();
    name = '';
    email = '';
    guest = false;
    if (!_disposed) notifyListeners();
  }

  void _applySettings(Map<String, dynamic> settings) {
    themeMode = switch (settings['theme']) {
      'LIGHT' => ThemeMode.light,
      'DARK' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    fontScale = ((settings['fontSize'] as num?)?.toDouble() ?? 16) / 16;
    speechSpeed = (settings['speechSpeed'] as num?)?.toDouble() ?? 1;
    speechPitch = (settings['speechPitch'] as num?)?.toDouble() ?? 1;
    highContrast = settings['highContrast'] == true;
    autoSpeak = settings['autoSpeak'] == true;
    avatarColor = (settings['avatarColor'] as num?)?.toInt() ?? 0;
  }

  Conversation _conversation(Map<String, dynamic> data) => Conversation(
    id: '${data['_id']}',
    content: '${data['content']}',
    createdAt: DateTime.parse('${data['createdAt']}'),
    direction: switch (data['direction']) {
      'SIGN_TO_SPEECH' => ConversationDirection.signToSpeech,
      'SPEECH_TO_TEXT' => ConversationDirection.speechToText,
      _ => ConversationDirection.text,
    },
    favorite: data['favorite'] == true,
  );
  Future<bool> synchronize() async {
    if (service == null) return true;
    final epoch = _epoch, load = ++_loadEpoch, revision = _revision;
    update(() {
      syncing = true;
      error = null;
    });
    try {
      final data = await Future.wait<dynamic>([
        service!.profile(),
        service!.settings(),
        service!.conversations(),
        service!.favorites(),
      ]);
      if (!isCurrent(epoch) || load != _loadEpoch) return false;
      if (revision != _revision) return false;
      update(() {
        final profile = data[0] as Map<String, dynamic>;
        name = '${profile['displayName']}';
        email = '${profile['email'] ?? ''}';
        avatarUrl = '${profile['avatarUrl'] ?? ''}';
        accountType = '${profile['accountType']}';
        _applySettings(data[1] as Map<String, dynamic>);
        final conversations = data[2] as Map<String, dynamic>;
        history
          ..clear()
          ..addAll(
            (conversations['items'] as List).map(
              (item) => _conversation(Map<String, dynamic>.from(item)),
            ),
          );
        historyPage = 1;
        historyPages = (conversations['pages'] as num).toInt();
        historySearch = '';
        historyDirection = null;
        historyFavorite = null;
        favorites
          ..clear()
          ..addAll((data[3] as List).map((item) => '${item['entryId']}'));
        _ready = true;
        online = true;
        lastSync = DateTime.now();
      });
      return true;
    } catch (failure) {
      if (isCurrent(epoch) && load == _loadEpoch) {
        update(() {
          error = _message(failure);
          online = false;
        });
      }
      return false;
    } finally {
      if (isCurrent(epoch) && load == _loadEpoch) update(() => syncing = false);
    }
  }

  String _message(Object failure) => failure is ApiException
      ? failure.message
      : 'Không tải/lưu được dữ liệu. Vui lòng thử lại.';
  Future<bool> _mutate(Future<void> Function(int epoch) work) async {
    final epoch = _epoch;
    if (persisted && (!isCurrent(epoch) || !ready)) return false;
    try {
      await work(epoch);
      if (persisted && !isCurrent(epoch)) return false;
      _revision++;
      update(() => error = null);
      return true;
    } catch (failure) {
      if (!persisted || isCurrent(epoch)) {
        update(() => error = _message(failure));
      }
      return false;
    }
  }

  Future<bool> saveProfile(Map<String, dynamic> body) => _mutate((epoch) async {
    final profile = service == null ? body : await service!.saveProfile(body);
    if (persisted && !isCurrent(epoch)) return;
    update(() {
      name = '${profile['displayName'] ?? name}';
      email = '${profile['email'] ?? email}';
      avatarUrl = '${profile['avatarUrl'] ?? avatarUrl}';
    });
  });
  Future<bool> saveSettings(Map<String, dynamic> body) {
    final epoch = _epoch;
    final result = Completer<bool>();
    _settingsQueue = _settingsQueue.then((_) async {
      if (persisted && !isCurrent(epoch)) {
        result.complete(false);
        return;
      }
      result.complete(
        await _mutate((captured) async {
          if (service == null) return;
          final settings = await service!.saveSettings(body);
          if (isCurrent(captured)) update(() => _applySettings(settings));
        }),
      );
    });
    return result.future;
  }

  Future<bool> loadHistory({
    bool more = false,
    String? search,
    String? direction,
    bool? favorite,
  }) async {
    if (service == null) return true;
    final epoch = _epoch, load = ++_loadEpoch;
    final page = more ? historyPage + 1 : 1;
    update(() {
      syncing = true;
      error = null;
    });
    try {
      final result = await service!.conversations(
        page: page,
        search: search ?? historySearch,
        direction: direction ?? (more ? historyDirection : null),
        favorite: favorite ?? (more ? historyFavorite : null),
      );
      if (!isCurrent(epoch) || load != _loadEpoch) return false;
      update(() {
        if (!more) history.clear();
        history.addAll(
          (result['items'] as List).map(
            (item) => _conversation(Map<String, dynamic>.from(item)),
          ),
        );
        historyPage = page;
        historyPages = (result['pages'] as num).toInt();
        if (!more) {
          historySearch = search ?? '';
          historyDirection = direction;
          historyFavorite = favorite;
        }
      });
      return true;
    } catch (failure) {
      if (isCurrent(epoch) && load == _loadEpoch) {
        update(() => error = _message(failure));
      }
      return false;
    } finally {
      if (isCurrent(epoch) && load == _loadEpoch) update(() => syncing = false);
    }
  }

  void addWord(String word) {
    final text = word.trim();
    if (text.isNotEmpty) update(() => sentence.add(text));
  }

  String get sentenceText {
    final text = sentence.join(' ').trim();
    if (text.isEmpty) return '';
    return RegExp(r'[.!?…]$').hasMatch(text) ? text : '$text.';
  }

  Future<bool> toggleSign(String word) {
    if (service == null) {
      update(() {
        if (!favorites.add(word)) favorites.remove(word);
      });
      return Future.value(true);
    }
    final enabled = !favorites.contains(word);
    return _mutate((epoch) async {
      await service!.setFavorite(word, enabled);
      if (isCurrent(epoch)) {
        update(() {
          if (enabled) {
            favorites.add(word);
          } else {
            favorites.remove(word);
          }
        });
      }
    });
  }

  void selectSign(SignEntry entry) => update(() => selectedSign = entry);
  void selectConversation(Conversation entry) =>
      update(() => selectedHistoryId = entry.id);
  Future<bool> selectHistoryId(String id) => _mutate((epoch) async {
    if (service == null) {
      update(() => selectedHistoryId = id);
      return;
    }
    final item = _conversation(await service!.conversation(id));
    if (isCurrent(epoch)) {
      update(() {
        history.removeWhere((entry) => entry.id == id);
        history.add(item);
        selectedHistoryId = id;
      });
    }
  });
  Conversation? get selectedConversation {
    for (final entry in history) {
      if (entry.id == selectedHistoryId) return entry;
    }
    return null;
  }

  Future<bool> toggleConversation(Conversation entry) {
    if (service == null) {
      update(() => entry.favorite = !entry.favorite);
      return Future.value(true);
    }
    final favorite = !entry.favorite;
    return _mutate((epoch) async {
      await service!.updateConversation(entry.id, {'favorite': favorite});
      if (isCurrent(epoch)) update(() => entry.favorite = favorite);
    });
  }

  Future<bool> saveConversation(String text, ConversationDirection direction) {
    if (text.trim().isEmpty) return Future.value(false);
    void insert(Conversation entry) => update(() {
      history.insert(0, entry);
      selectedHistoryId = entry.id;
    });
    if (service == null) {
      insert(
        Conversation(
          id: '${DateTime.now().microsecondsSinceEpoch}-${_localConversationSequence++}',
          content: text.trim(),
          createdAt: DateTime.now(),
          direction: direction,
        ),
      );
      return Future.value(true);
    }
    return _mutate((epoch) async {
      final data = await service!.saveConversation(
        text.trim(),
        switch (direction) {
          ConversationDirection.signToSpeech => 'SIGN_TO_SPEECH',
          ConversationDirection.speechToText => 'SPEECH_TO_TEXT',
          ConversationDirection.text => 'TEXT',
        },
      );
      if (isCurrent(epoch)) insert(_conversation(data));
    });
  }

  Future<bool> removeConversation(String id) => _mutate((epoch) async {
    if (service != null) await service!.deleteConversation(id);
    if (!persisted || isCurrent(epoch)) {
      update(() {
        history.removeWhere((item) => item.id == id);
        if (selectedHistoryId == id) selectedHistoryId = null;
      });
    }
  });
  Future<bool> clearHistory() => _mutate((epoch) async {
    if (service != null) await service!.clearHistory();
    if (!persisted || isCurrent(epoch)) {
      update(() {
        history.clear();
        selectedHistoryId = null;
      });
    }
  });
  Future<bool> clearPersistedData() => _mutate((epoch) async {
    if (service != null) await service!.clearData();
    if (!persisted || isCurrent(epoch)) {
      update(() {
        history.clear();
        favorites.clear();
        sentence.clear();
        selectedHistoryId = null;
        _applySettings({});
      });
    }
  });
  void clearLocalData() => update(() {
    history.clear();
    favorites.clear();
    sentence.clear();
    selectedHistoryId = null;
  });
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
