import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/learning/collection_screens.dart';
import 'package:sign_voice/features/learning/collection_widgets.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/user/avatar_picker.dart';

import 'auth_fixtures.dart';

class CollectionsFixture extends LearningService {
  static const id = 'aaaaaaaaaaaaaaaaaaaaaaaa',
      entry = 'bbbbbbbbbbbbbbbbbbbbbbbb',
      code = 'dddddddddddddddddddddddddddddddd';
  final collections = <LearningRecord>[
    {
      '_id': id,
      'name': 'Đi khám bệnh',
      'description': 'Bộ ký hiệu cho tình huống hằng ngày.',
      'shared': false,
      'shareCode': '',
    },
  ];
  final notes = <String, String>{entry: 'Ghi chú chỉ của tôi'};
  final privateWords = <LearningRecord>[];
  int privateWrites = 0, attachments = 0;
  final dictionary = List.generate(
    12,
    (i) => <String, dynamic>{
      '_id': i == 0 ? entry : i.toRadixString(16).padLeft(24, '0'),
      'word': i == 0 ? 'xin chào' : 'Ký hiệu $i',
      'thumbnailUrl': '',
      'imageUrls': <String>[],
      'videoUrl': '',
      'definition': 'Mô tả đáng tin cậy.',
      'stage': i == 0 ? 'REVIEW' : 'LEARNING',
    },
  );
  final members = <String, Set<String>>{
    id: {entry, '000000000000000000000001'},
  };
  int reads = 0,
      creates = 0,
      adds = 0,
      shares = 0,
      imports = 0,
      noteReads = 0,
      publishes = 0;
  bool failRead = false, failWrite = false;
  Completer<void>? addGate;
  final searchGates = <String, Completer<LearningRecord>>{};
  LearningRecord clone(LearningRecord value) =>
      LearningRecord.from(jsonDecode(jsonEncode(value)) as Map);
  LearningRecord metadata(LearningRecord row) => {
    ...row,
    'wordCount': members[row['_id']]?.length ?? 0,
    'libraryWordCount': members[row['_id']]?.length ?? 0,
    'personalWordCount': privateWords
        .where((word) => word['collectionId'] == row['_id'])
        .length,
    'reviewCount': 1,
  };
  @override
  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async {
    reads++;
    if (failRead) throw ApiException(message: 'Mạng đang gián đoạn');
    if (searchGates.containsKey(search)) return searchGates[search]!.future;
    var rows = <LearningRecord>[];
    LearningRecord? collection;
    final shared = path.startsWith('/shared-collections/');
    if (path == '/sign-collections' || path == '/shared-collections') {
      rows = collections
          .where(
            (row) =>
                path != '/shared-collections' || row['discoverable'] == true,
          )
          .where(
            (row) =>
                '${row['name']}'.toLowerCase().contains(search.toLowerCase()),
          )
          .map(metadata)
          .toList();
    } else {
      final parts = path.split('/');
      final collectionId = shared ? id : parts[2];
      collection = metadata(
        collections.firstWhere((row) => row['_id'] == collectionId),
      );
      rows = dictionary
          .where(
            (row) =>
                path.endsWith('/candidates') ||
                members[collectionId]!.contains(row['_id']),
          )
          .map(
            (row) => {
              ...row,
              if (path.endsWith('/candidates'))
                'inCollection': members[collectionId]!.contains(row['_id']),
              if (!shared) 'personalNote': notes[row['_id']] ?? '',
            },
          )
          .where((row) => '${row['word']}'.contains(search))
          .toList();
      if (path.endsWith('/personal-words/available')) {
        rows = privateWords
            .where(
              (row) =>
                  row['collectionId'] == null &&
                  '${row['word']}'.contains(search),
            )
            .toList();
      } else if (!shared && !path.endsWith('/candidates')) {
        rows.addAll(
          privateWords.where(
            (row) =>
                row['collectionId'] == collectionId &&
                '${row['word']}'.contains(search),
          ),
        );
      }
    }
    return clone({
      'items': rows.skip((page - 1) * 10).take(10).toList(),
      'pagination': {
        'page': page,
        'pages': (rows.length / 10).ceil().clamp(1, 100),
        'total': rows.length,
      },
      'collection': ?collection,
      'summary': {'total': rows.length, 'review': 1, 'remembered': 0},
    });
  }

  @override
  Future<LearningRecord> createCollection(
    String name,
    String description, {
    String avatarImage = '',
  }) async {
    creates++;
    if (failWrite) throw ApiException(message: 'Chưa lưu được bộ');
    final row = {
      '_id': creates.toRadixString(16).padLeft(24, '0'),
      'name': name,
      'description': description,
      'avatarImage': avatarImage,
      'shared': false,
      'shareCode': '',
    };
    collections.add(row);
    members[row['_id'] as String] = {};
    return metadata(row);
  }

  @override
  Future<LearningRecord> updateCollection(
    String id,
    String name,
    String description, {
    String? avatarImage,
  }) async {
    if (failWrite) throw ApiException(message: 'Chưa lưu được bộ');
    final row = collections.firstWhere((row) => row['_id'] == id);
    row['name'] = name;
    row['description'] = description;
    if (avatarImage != null) row['avatarImage'] = avatarImage;
    return metadata(row);
  }

  @override
  Future<LearningRecord> addCollectionEntries(
    String id,
    List<String> entries,
  ) async {
    adds++;
    await addGate?.future;
    if (failWrite) throw ApiException(message: 'Chưa thêm được từ');
    members[id]!.addAll(entries);
    return {'added': entries.length};
  }

  @override
  Future<LearningRecord> removeCollectionEntry(
    String id,
    String entryId,
  ) async {
    members[id]!.remove(entryId);
    return {};
  }

  @override
  Future<LearningRecord> shareCollection(String id, bool enabled) async {
    shares++;
    final row = collections.firstWhere((row) => row['_id'] == id);
    row['shared'] = enabled;
    row['shareCode'] = enabled ? code : '';
    if (!enabled) row['discoverable'] = false;
    return {
      'shared': enabled,
      'shareCode': enabled ? code : '',
      'discoverable': row['discoverable'] == true,
    };
  }

  @override
  Future<LearningRecord> publishCollection(String id, bool enabled) async {
    publishes++;
    if (failWrite) throw ApiException(message: 'Chưa đăng được bộ');
    final row = collections.firstWhere((row) => row['_id'] == id);
    row['discoverable'] = enabled;
    if (enabled) {
      row['shareCode'] = code;
      row['shared'] = true;
    }
    return metadata(row);
  }

  @override
  Future<LearningRecord> importCollection(String code) async {
    imports++;
    return {'_id': id};
  }

  @override
  Future<LearningRecord> signNote(String id) async {
    noteReads++;
    return {'text': notes[id] ?? ''};
  }

  @override
  Future<LearningRecord> saveSignNote(String id, String text) async {
    if (failWrite) throw ApiException(message: 'Chưa lưu được ghi chú');
    notes[id] = text;
    return {'text': text};
  }

  @override
  Future<LearningRecord> deleteCollection(String id) async {
    collections.removeWhere((row) => row['_id'] == id);
    return {};
  }

  @override
  Future<LearningRecord> saveCollectionWord(
    String collectionId,
    LearningRecord word, {
    String? id,
  }) async {
    privateWrites++;
    if (failWrite) throw ApiException(message: 'Chưa lưu được từ riêng');
    final value = {
      ...word,
      '_id': id ?? 'cccccccccccccccccccccccc',
      'collectionId': collectionId,
      'isPersonal': true,
      'stage': 'PRIVATE',
      'thumbnailUrl': word['imageUrl'],
      'imageUrls': <String>[],
    };
    privateWords.removeWhere((row) => row['_id'] == value['_id']);
    privateWords.add(value);
    return value;
  }

  @override
  Future<LearningRecord> attachCollectionWords(
    String id,
    List<String> wordIds,
  ) async {
    attachments++;
    for (final row in privateWords.where(
      (word) => wordIds.contains(word['_id']),
    )) {
      row['collectionId'] = id;
    }
    return {};
  }

  @override
  Future<LearningRecord> deleteCollectionWord(String id, String wordId) async {
    privateWords.removeWhere((row) => row['_id'] == wordId);
    return {};
  }

  @override
  Future<LearningRecord> collectionWord(String id, String wordId) async =>
      privateWords.firstWhere((row) => row['_id'] == wordId);
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    CollectionsFixture service, {
    String route = '/learn?tab=2',
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final state = AppState()
      ..fontScale = scale
      ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: state,
        learningService: service,
        initialScreen: route,
      ),
    );
    await tester.pumpAndSettle();
    state.update(() {
      state.fontScale = scale;
      state.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
    await tester.pumpAndSettle();
    final pageContext = tester.element(find.byType(Scaffold).first);
    expect(
      Theme.of(pageContext).brightness,
      dark ? Brightness.dark : Brightness.light,
    );
    expect(MediaQuery.textScalerOf(pageContext).scale(16), 16 * scale);
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates a collection with inline validation and opens its detail',
    (tester) async {
      final service = CollectionsFixture();
      await mount(tester, service);
      expect(find.text('Bộ sưu tập ký hiệu'), findsOneWidget);
      expect(find.text('Đi khám bệnh'), findsOneWidget);
      await tap(tester, find.text('Tạo bộ sưu tập'));
      await tap(tester, find.text('Lưu bộ'));
      expect(find.text('Nhập tên bộ sưu tập.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Gọi món');
      await tap(tester, find.text('Lưu bộ'));
      expect(service.creates, 1);
      expect(find.byType(SignCollectionScreen), findsOneWidget);
      expect(find.text('Gọi món'), findsNWidgets(2));
    },
  );
  testWidgets(
    'legacy private route opens collections without an outside private cards menu',
    (tester) async {
      await mount(tester, CollectionsFixture(), route: '/learn/personal');
      expect(find.byType(SignCollectionsScreen), findsOneWidget);
      expect(find.text('Thẻ riêng đã tạo'), findsNothing);
    },
  );
  testWidgets(
    'creates a private word inside a collection, preserves a failed form and edits or deletes it',
    (tester) async {
      final service = CollectionsFixture();
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}',
      );
      await tap(tester, find.text('Thêm từ'));
      await tap(tester, find.text('Tạo từ riêng'));
      await tap(tester, find.text('Lưu từ'));
      expect(service.privateWrites, 0);
      await tester.enterText(find.byType(TextFormField).at(0), 'Chúc ngủ ngon');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Lời chúc trước khi đi ngủ.',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Chúc bạn ngủ ngon.',
      );
      service.failWrite = true;
      await tap(tester, find.text('Lưu từ'));
      expect(find.text('Chưa lưu được từ riêng'), findsOneWidget);
      expect(find.text('Chúc ngủ ngon'), findsOneWidget);
      service.failWrite = false;
      await tap(tester, find.text('Lưu từ'));
      expect(service.privateWords.single['usageExample'], 'Chúc bạn ngủ ngon.');
      expect(
        service.privateWords.single['collectionId'],
        CollectionsFixture.id,
      );
      await tap(tester, find.text('Chỉnh sửa từ riêng'));
      await tester.enterText(find.byType(TextFormField).at(1), 'Nghĩa mới');
      await tap(tester, find.text('Lưu từ'));
      expect(service.privateWords.single['definition'], 'Nghĩa mới');
      await tap(tester, find.byTooltip('Tùy chọn ký hiệu Chúc ngủ ngon'));
      await tap(tester, find.text('Xóa từ riêng'));
      expect(service.privateWords, isNotEmpty);
      await tap(tester, find.text('Xóa'));
      expect(service.privateWords, isEmpty);
    },
  );
  testWidgets(
    'offers preserved private words and attaches them inside the collection',
    (tester) async {
      final service = CollectionsFixture()
        ..privateWords.add({
          '_id': 'cccccccccccccccccccccccc',
          'word': 'Từ riêng cũ',
          'definition': 'Giữ nguyên',
          'isPersonal': true,
        });
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}',
      );
      await tap(tester, find.text('Thêm từ'));
      await tap(tester, find.text('Thêm từ riêng đã có'));
      await tap(tester, find.widgetWithText(CheckboxListTile, 'Từ riêng cũ'));
      await tap(tester, find.text('Thêm 1 ký hiệu'));
      expect(service.attachments, 1);
      expect(
        service.privateWords.single['collectionId'],
        CollectionsFixture.id,
      );
      expect(find.byType(SignCollectionScreen), findsOneWidget);
    },
  );
  testWidgets(
    'collection editor keeps chosen avatar after a failed save and supports removing it',
    (tester) async {
      final service = CollectionsFixture();
      await mount(tester, service);
      final image = AvatarSelection(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
        ),
        'png',
      );
      final context = tester.element(find.byType(SignCollectionsScreen));
      final dialog = editSignCollection(
        context,
        collection: service.collections.first,
        avatarPicker: () async => image,
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Thêm ảnh đại diện'));
      expect(find.text('Bỏ ảnh đại diện'), findsOneWidget);
      service.failWrite = true;
      await tap(tester, find.text('Lưu bộ'));
      expect(find.text('Chưa lưu được bộ'), findsOneWidget);
      expect(find.text('Bỏ ảnh đại diện'), findsOneWidget);
      service.failWrite = false;
      await tap(tester, find.text('Lưu bộ'));
      await dialog;
      expect(service.collections.first['avatarImage'], image.dataUrl);
      final next = editSignCollection(
        context,
        collection: service.collections.first,
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Bỏ ảnh đại diện'));
      await tap(tester, find.text('Lưu bộ'));
      await next;
      expect(service.collections.first['avatarImage'], '');
    },
  );
  testWidgets(
    'word selection persists across refresh and submits once while saving',
    (tester) async {
      final service = CollectionsFixture()..addGate = Completer<void>();
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}/add',
      );
      final row = find.widgetWithText(CheckboxListTile, 'Ký hiệu 2');
      await tap(tester, row);
      ApiClient.instance.libraryChanged.value++;
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(row).value, isTrue);
      await tester.ensureVisible(find.text('Thêm 1 ký hiệu'));
      await tester.tap(find.text('Thêm 1 ký hiệu'));
      await tester.pump();
      expect(service.adds, 1);
      expect(find.text('Đang thêm…'), findsOneWidget);
      service.addGate!.complete();
      await tester.pumpAndSettle();
      expect(
        service.members[CollectionsFixture.id],
        contains('000000000000000000000002'),
      );
      expect(find.byType(SignCollectionScreen), findsOneWidget);
    },
  );
  testWidgets(
    'collection actions have separated touch areas and private edits warn before leaving',
    (tester) async {
      await mount(tester, CollectionsFixture());
      final create = find.widgetWithText(CollectionAction, 'Tạo bộ sưu tập');
      final discover = find.widgetWithText(
        CollectionAction,
        'Khám phá bộ công khai',
      );
      final receive = find.widgetWithText(
        CollectionAction,
        'Tôi có mã hoặc liên kết',
      );
      for (final item in [create, discover, receive]) {
        expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getTopLeft(discover).dy - tester.getBottomLeft(create).dy,
        greaterThanOrEqualTo(12),
      );
      expect(
        tester.getTopLeft(receive).dy - tester.getBottomLeft(discover).dy,
        greaterThanOrEqualTo(12),
      );
      await tap(tester, find.text('Đi khám bệnh'));
      await tap(tester, find.text('Thêm từ'));
      await tap(tester, find.text('Tạo từ riêng'));
      await tester.enterText(
        find.byType(TextFormField).first,
        'Nội dung chưa lưu',
      );
      await tap(tester, find.byTooltip('Đóng'));
      expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
      await tap(tester, find.text('Viết tiếp'));
      expect(find.text('Nội dung chưa lưu'), findsOneWidget);
      await tap(tester, find.byTooltip('Đóng'));
      await tap(tester, find.text('Bỏ thay đổi'));
      expect(find.byType(SignCollectionScreen), findsOneWidget);
    },
  );
  testWidgets('leaving the picker warns about unsaved selections', (
    tester,
  ) async {
    final service = CollectionsFixture();
    await mount(
      tester,
      service,
      route: '/collections/${CollectionsFixture.id}/add',
    );
    await tap(tester, find.widgetWithText(CheckboxListTile, 'Ký hiệu 2'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ các từ đang chọn?'), findsOneWidget);
    await tap(tester, find.text('Chọn tiếp'));
    expect(find.text('Thêm 1 ký hiệu'), findsOneWidget);
  });
  testWidgets(
    'notes use the loaded private value and update without a second page read',
    (tester) async {
      final service = CollectionsFixture();
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}',
      );
      final reads = service.reads;
      await tap(tester, find.text('Sửa ghi chú').first);
      expect(find.text('Ghi chú chỉ của tôi'), findsWidgets);
      expect(service.noteReads, 0);
      await tester.enterText(find.byType(TextField).last, 'Cách nhớ mới');
      await tap(tester, find.text('Lưu ghi chú'));
      expect(service.notes[CollectionsFixture.entry], 'Cách nhớ mới');
      expect(service.reads, reads);
      expect(find.text('Cách nhớ mới'), findsOneWidget);
    },
  );
  testWidgets(
    'receiving a collection pastes only after a tap and previews valid links',
    (tester) async {
      var clipboardReads = 0;
      String copied = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            clipboardReads++;
            return {'text': copied};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, CollectionsFixture());
      await tap(tester, find.text('Tôi có mã hoặc liên kết'));
      expect(clipboardReads, 0);
      final action = find.widgetWithText(FilledButton, 'Xem trước bộ sưu tập');
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      await tap(tester, find.text('Dán từ bộ nhớ'));
      expect(
        find.text('Chưa có mã hoặc liên kết trong bộ nhớ sao chép.'),
        findsOneWidget,
      );
      copied = 'not-a-collection-link';
      await tap(tester, find.text('Dán từ bộ nhớ'));
      expect(find.textContaining('Dùng liên kết bộ sưu tập'), findsOneWidget);
      copied =
          'https://example.com/#/collections/shared/${CollectionsFixture.code}';
      await tap(tester, find.text('Dán từ bộ nhớ'));
      expect(clipboardReads, 3);
      await tap(tester, action);
      expect(find.byType(SharedSignCollectionScreen), findsOneWidget);
      expect(find.text('Ghi chú chỉ của tôi'), findsNothing);
    },
  );
  testWidgets(
    'discovery needs no share code and an empty catalog gives a useful next step',
    (tester) async {
      final service = CollectionsFixture();
      await mount(tester, service);
      await tap(tester, find.text('Khám phá bộ công khai'));
      expect(find.byType(PublicSignCollectionsScreen), findsOneWidget);
      expect(find.text('Chưa có bộ công khai'), findsOneWidget);
      service.collections.first.addAll({
        'discoverable': true,
        'shared': true,
        'shareCode': CollectionsFixture.code,
      });
      await tap(tester, find.byTooltip('Làm mới bộ công khai'));
      await tap(tester, find.text('Đi khám bệnh'));
      expect(find.byType(SharedSignCollectionScreen), findsOneWidget);
    },
  );
  testWidgets(
    'public listing is a separate opt-in and QR encodes the revocable preview link',
    (tester) async {
      final service = CollectionsFixture();
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}',
      );
      await tap(tester, find.byTooltip('Quản lý bộ'));
      await tap(tester, find.text('Chia sẻ bộ'));
      await tap(tester, find.text('Hiện trong khám phá công khai'));
      expect(service.publishes, 0);
      await tap(tester, find.text('Để riêng tư'));
      expect(service.publishes, 0);
      await tap(tester, find.text('Hiện trong khám phá công khai'));
      await tap(tester, find.text('Đăng công khai'));
      expect(service.publishes, 1);
      await tap(tester, find.text('Hiện mã QR'));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).backgroundColor,
        Colors.white,
      );
      await tap(tester, find.text('Hiện trong khám phá công khai'));
      expect(service.publishes, 2);
      expect(find.text('Sao chép liên kết'), findsOneWidget);
      await tap(tester, find.text('Tắt mã chia sẻ'));
      expect(find.byType(QrImageView), findsNothing);
    },
  );
  testWidgets(
    'native sharing uses the system sheet and cancellation does not publish the collection',
    (tester) async {
      MethodCall? request;
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        request = call;
        return 'dev.fluttercommunity.plus/share/dismissed';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final service = CollectionsFixture();
      await mount(
        tester,
        service,
        route: '/collections/${CollectionsFixture.id}',
      );
      await tap(tester, find.byTooltip('Quản lý bộ'));
      await tap(tester, find.text('Chia sẻ bộ'));
      await tap(tester, find.text('Bật chia sẻ'));
      await tap(tester, find.text('Chia sẻ qua ứng dụng'));
      expect(request?.method, 'share');
      expect(
        (request!.arguments as Map)['text'],
        contains('/#/collections/shared/${CollectionsFixture.code}'),
      );
      expect(service.publishes, 0);
    },
  );
  testWidgets('sharing is opt-in, copies the link and can revoke the code', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final service = CollectionsFixture();
    await mount(
      tester,
      service,
      route: '/collections/${CollectionsFixture.id}',
    );
    await tap(tester, find.byTooltip('Quản lý bộ'));
    await tap(tester, find.text('Chia sẻ bộ'));
    expect(service.shares, 0);
    await tap(tester, find.text('Bật chia sẻ'));
    expect(service.shares, 1);
    await tap(tester, find.text('Sao chép liên kết'));
    expect(
      copied,
      endsWith('/#/collections/shared/${CollectionsFixture.code}'),
    );
    await tap(tester, find.text('Tắt mã chia sẻ'));
    expect(service.shares, 2);
    expect(find.text(CollectionsFixture.code), findsNothing);
  });
  testWidgets(
    'a shared preview does not show personal notes and imports into the account',
    (tester) async {
      final service = CollectionsFixture();
      await mount(
        tester,
        service,
        route: '/collections/shared/${CollectionsFixture.code}',
      );
      expect(find.text('Ghi chú chỉ của tôi'), findsNothing);
      await tap(tester, find.text('Lưu vào bộ sưu tập của tôi'));
      expect(service.imports, 1);
      expect(find.byType(SignCollectionScreen), findsOneWidget);
    },
  );
  testWidgets('failed loading can be retried without leaving the page', (
    tester,
  ) async {
    final service = CollectionsFixture()..failRead = true;
    await mount(tester, service);
    expect(find.text('Mạng đang gián đoạn'), findsOneWidget);
    service.failRead = false;
    await tap(tester, find.text('Thử lại'));
    expect(find.text('Đi khám bệnh'), findsOneWidget);
  });
  testWidgets('late search replies cannot replace the newer search result', (
    tester,
  ) async {
    final service = CollectionsFixture();
    await mount(tester, service);
    service.searchGates['old'] = Completer<LearningRecord>();
    service.searchGates['new'] = Completer<LearningRecord>();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    service.searchGates['new']!.complete({
      'items': [
        {'_id': CollectionsFixture.id, 'name': 'Bộ mới', 'wordCount': 1},
      ],
      'pagination': {'pages': 1, 'total': 1},
    });
    await tester.pumpAndSettle();
    service.searchGates['old']!.complete({
      'items': [
        {'_id': CollectionsFixture.id, 'name': 'Bộ cũ', 'wordCount': 1},
      ],
      'pagination': {'pages': 1, 'total': 1},
    });
    await tester.pumpAndSettle();
    expect(find.text('Bộ mới'), findsOneWidget);
    expect(find.text('Bộ cũ'), findsNothing);
  });
  test('validates codes and extracts only a code from links', () {
    expect(
      collectionShareCode(
        ' https://example.com/#/collections/shared/${CollectionsFixture.code} ',
      ),
      CollectionsFixture.code,
    );
    expect(
      collectionShareCode(CollectionsFixture.code),
      CollectionsFixture.code,
    );
    expect(collectionShareCode('javascript:alert(1)'), isNull);
    expect(collectionShareCode('abc'), isNull);
  });
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(800, 1024),
    ]) {
      testWidgets(
        'collection avatar editor and private form fit text 2x $size dark=$dark',
        (tester) async {
          await mount(
            tester,
            CollectionsFixture(),
            route: '/collections/${CollectionsFixture.id}',
            size: size,
            scale: 2,
            dark: dark,
          );
          await tap(tester, find.byTooltip('Quản lý bộ'));
          await tap(tester, find.text('Chỉnh sửa bộ'));
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height < 500 ? 160 : 260,
          );
          await tester.enterText(find.byType(TextFormField).first, 'Bộ mới');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, find.text('Hủy'));
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          await tap(tester, find.text('Thêm từ'));
          await tap(tester, find.text('Tạo từ riêng'));
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height < 500 ? 160 : 260,
          );
          await tester.enterText(find.byType(TextFormField).first, 'Từ riêng');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, find.text('Lưu từ'));
          expect(find.text('Thêm ý nghĩa để dễ ôn tập.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
      for (final route in [
        '/learn?tab=2',
        '/collections/discover',
        '/collections/${CollectionsFixture.id}',
        '/collections/${CollectionsFixture.id}/add',
        '/collections/shared/${CollectionsFixture.code}',
      ]) {
        testWidgets('collections fit large text $size dark=$dark $route', (
          tester,
        ) async {
          await mount(
            tester,
            CollectionsFixture(),
            route: route,
            size: size,
            scale: 2,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
          if (route.endsWith('/add')) {
            await tester.enterText(find.byType(TextField), 'Ký hiệu');
            tester.view.viewInsets = FakeViewPadding(
              bottom: size.height < 500 ? 160 : 260,
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(field).bottom,
              lessThanOrEqualTo(size.height - (size.height < 500 ? 160 : 260)),
            );
          }
        });
      }
      testWidgets('sharing QR and publication fit text 2x $size dark=$dark', (
        tester,
      ) async {
        await mount(
          tester,
          CollectionsFixture(),
          route: '/collections/${CollectionsFixture.id}',
          size: size,
          scale: 2,
          dark: dark,
        );
        await tap(tester, find.byTooltip('Quản lý bộ'));
        await tap(tester, find.text('Chia sẻ bộ'));
        await tap(tester, find.text('Bật chia sẻ'));
        await tap(tester, find.text('Hiện mã QR'));
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Hiện trong khám phá công khai'));
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Để riêng tư'));
        await tap(tester, find.text('Đóng'));
      });
      testWidgets('receive dialog fits keyboard and text 2x $size dark=$dark', (
        tester,
      ) async {
        await mount(
          tester,
          CollectionsFixture(),
          size: size,
          scale: 2,
          dark: dark,
        );
        await tap(tester, find.text('Tôi có mã hoặc liên kết'));
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height < 500 ? 160 : 260,
        );
        await tester.enterText(find.byType(TextFormField), 'abc');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tap(tester, find.byTooltip('Đóng hộp nhận bộ'));
      });
    }
  }
}
