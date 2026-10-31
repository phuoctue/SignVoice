import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/features/learning/learning_page_controller.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

void main() {
  test(
    'cached content renders immediately while a fresh read is pending',
    () async {
      final fresh = Completer<LearningPage>();
      final controller = LearningPageController(
        cachedPage: (_) => LearningPage(
          items: [
            {'word': 'đã lưu'},
          ],
        ),
        loadPage: (_) => fresh.future,
        errorMessage: 'offline',
      );
      addTearDown(controller.dispose);
      final loading = controller.load();
      expect(controller.loading, isFalse);
      expect(controller.data!.items.single['word'], 'đã lưu');
      fresh.complete(
        LearningPage(
          items: [
            {'word': 'mới'},
          ],
        ),
      );
      await loading;
      expect(controller.data!.items.single['word'], 'mới');
    },
  );
  test('acknowledged ratings update counts without hiding the page during reconciliation', () async {
    final refresh = Completer<LearningPage>();
    var calls = 0;
    final controller = LearningPageController(
      loadPage: (_) async {
        if (calls++ > 0) return refresh.future;
        return LearningPage(
          items: [
            {'_id': 'one', 'stage': 'LEARNING'},
            {'_id': 'two', 'stage': 'LEARNING'},
          ],
          total: 2,
          summary: {'total': 2, 'learning': 2, 'remembered': 0, 'review': 0},
          enrolled: true,
        );
      },
      errorMessage: 'offline',
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.applyStage('one', 'REMEMBERED', filter: 'LEARNING');
    final reconciliation = controller.load(background: true);
    expect(controller.loading, isFalse);
    expect(controller.data!.items.single['_id'], 'two');
    expect(controller.data!.summary['remembered'], 1);
    expect(controller.data!.summary['learning'], 1);
    expect(controller.data!.total, 1);
    refresh.completeError(StateError('offline'));
    await reconciliation;
    expect(controller.data!.summary['remembered'], 1);
    expect(controller.error, 'offline');
  });

  test('a late earlier request cannot replace the latest page', () async {
    final first = Completer<LearningPage>();
    final second = Completer<LearningPage>();
    final controller = LearningPageController(
      loadPage: (page) => page == 1 ? first.future : second.future,
      errorMessage: 'Không tải được nội dung.',
    );
    addTearDown(controller.dispose);
    final oldRequest = controller.load();
    final latestRequest = controller.load(page: 2);
    second.complete(
      LearningPage(
        items: [
          {'word': 'mới'},
        ],
        pages: 2,
      ),
    );
    await latestRequest;
    first.complete(
      LearningPage(
        items: [
          {'word': 'cũ'},
        ],
      ),
    );
    await oldRequest;
    expect(controller.data!.items.single['word'], 'mới');
    expect(controller.page, 2);
    expect(controller.loading, isFalse);
  });

  test('an out of range page reloads the last available page', () async {
    final controller = LearningPageController(
      loadPage: (page) async => LearningPage(
        items: page == 1
            ? [
                {'word': 'còn lại'},
              ]
            : [],
        pages: 1,
      ),
      errorMessage: 'Không tải được nội dung.',
    );
    addTearDown(controller.dispose);
    await controller.load(page: 3);
    expect(controller.page, 1);
    expect(controller.data!.items.single['word'], 'còn lại');
  });

  test('an empty API page count cannot cause infinite reloads', () async {
    final controller = LearningPageController(
      loadPage: (_) async => LearningPage(items: [], pages: 0),
      errorMessage: 'Không tải được nội dung.',
    );
    addTearDown(controller.dispose);
    await controller.load(page: 2).timeout(const Duration(seconds: 1));
    expect(controller.page, 1);
    expect(controller.data!.items, isEmpty);
    expect(controller.loading, isFalse);
  });

  test('an API error is shown and cleared by a successful retry', () async {
    var offline = true;
    final controller = LearningPageController(
      loadPage: (_) async {
        if (offline) throw ApiException(message: 'Mất mạng', statusCode: 503);
        return LearningPage(
          items: [
            {'word': 'xin chào'},
          ],
        );
      },
      errorMessage: 'Không tải được nội dung.',
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.error, 'Mất mạng');
    expect(controller.loading, isFalse);
    offline = false;
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.data!.items.single['word'], 'xin chào');
  });

  test('disposing while loading ignores pending results and errors', () async {
    final response = Completer<LearningPage>();
    final controller = LearningPageController(
      loadPage: (_) => response.future,
      errorMessage: 'Không tải được nội dung.',
    );
    final request = controller.load();
    controller.dispose();
    response.completeError(StateError('late network failure'));
    await request;
  });
}
