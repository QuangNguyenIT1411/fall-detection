import 'dart:async';

import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/providers/buzzer_control_provider.dart';
import 'package:fall_detection_dashboard/services/buzzer_control_repository.dart';
import 'package:fall_detection_dashboard/widgets/buzzer_control_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_buzzer_repository.dart';

void main() {
  test('Device parses both buzzer fields and old records default ON', () {
    final json = FakeBuzzerRepository().current.toJson()
      ..remove('buzzer_enabled')
      ..remove('buzzer_updated_at');
    expect(Device.fromJson(json).buzzerEnabled, isTrue);
    json['buzzer_enabled'] = false;
    json['buzzer_updated_at'] = '2026-09-30T01:00:00Z';
    final device = Device.fromJson(json);
    expect(device.buzzerEnabled, isFalse);
    expect(device.buzzerUpdatedAt, DateTime.utc(2026, 9, 30, 1));
    expect(Device.fromJson(device.toJson()).buzzerEnabled, isFalse);
  });

  Future<void> render(WidgetTester tester, BuzzerControlProvider control) =>
      tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: control,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: BuzzerControlCard()),
            ),
          ),
        ),
      );

  testWidgets(
    'pending disables switch, OFF warning persists, server setting refreshed',
    (tester) async {
      final repo = FakeBuzzerRepository();
      final control = BuzzerControlProvider(repo);
      addTearDown(control.dispose);
      await control.refresh();
      await render(tester, control);
      repo.writeWait = Completer<BuzzerSetting>();
      await tester.tap(find.byKey(const Key('buzzer-switch')));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(control.device!.buzzerEnabled, isTrue);
      await control.setEnabled(false);
      expect(repo.writes, 1);
      repo.writeWait!.complete(BuzzerSetting(false, DateTime.utc(2026, 9, 30)));
      await tester.pumpAndSettle();
      expect(control.device!.buzzerEnabled, isFalse);
      expect(repo.reads, 2);
      expect(find.byKey(const Key('buzzer-disabled-warning')), findsOneWidget);
      expect(find.text('🔇 Còi đang tắt — Chế độ kiểm thử'), findsOneWidget);
      expect(
        find.text(
          'Thiết bị có thể mất tối đa khoảng 20 giây để nhận thay đổi.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Đã lưu cấu hình còi.'), findsOneWidget);
      repo.writeWait = null;
      await tester.tap(find.byKey(const Key('buzzer-switch')));
      await tester.pumpAndSettle();
      expect(find.text('🔊 Còi đang bật'), findsOneWidget);
      expect(find.byKey(const Key('buzzer-disabled-warning')), findsNothing);
    },
  );

  testWidgets('backend failure retains previous OFF value and warning', (
    tester,
  ) async {
    final repo = FakeBuzzerRepository()
      ..enabled = false
      ..failWrite = true;
    final control = BuzzerControlProvider(repo);
    addTearDown(control.dispose);
    await control.refresh();
    await render(tester, control);
    await tester.tap(find.byKey(const Key('buzzer-switch')));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    expect(find.byKey(const Key('buzzer-disabled-warning')), findsOneWidget);
    expect(
      find.text('Không thể lưu cấu hình còi. Vui lòng thử lại.'),
      findsOneWidget,
    );
  });

  test('stale refresh cannot undo saved setting; read failure retains Edge-confirmed OFF', () async {
    final repo = FakeBuzzerRepository();
    final control = BuzzerControlProvider(repo);
    addTearDown(control.dispose);
    await control.refresh();
    final oldDevice = repo.current;
    final wait = Completer<Device?>();
    repo.readWait = wait;
    final oldRefresh = control.refresh();
    await control.setEnabled(false);
    wait.complete(oldDevice);
    await oldRefresh;
    expect(control.device!.buzzerEnabled, isFalse);
    await control.setEnabled(true);
    repo.failRead = true;
    await control.setEnabled(false);
    expect(control.device!.buzzerEnabled, isFalse);
    expect(control.error, contains('Đã lưu nhưng chưa thể làm mới'));
  });

  test('logout/dispose during request prevents late notifications', () async {
    final repo = FakeBuzzerRepository();
    final control = BuzzerControlProvider(repo);
    await control.refresh();
    repo.writeWait = Completer<BuzzerSetting>();
    final pending = control.setEnabled(false);
    control.dispose();
    repo.writeWait!.complete(BuzzerSetting(false, DateTime.utc(2026, 9, 30)));
    await pending;
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('OFF warning and switch fit at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final control = BuzzerControlProvider(
        FakeBuzzerRepository()..enabled = false,
      );
      addTearDown(control.dispose);
      await control.refresh();
      await render(tester, control);
      expect(find.text('Còi thiết bị'), findsOneWidget);
      expect(find.byKey(const Key('buzzer-disabled-warning')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
