// The in-app toolbar end to end: latched with `latchConfiguration(toolbar:
// ...)` (what `DevicePreview.enable(toolbar: ...)` does), it must start on a
// device, reserve its room in the fit, and take taps in the letterbox while
// the app keeps taking the ones on the simulated screen.
//
// This lives in its own file because a latched configuration is consumed by
// the one binding a process can construct.

import 'dart:ui' as ui;

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:device_preview/src/toolbar/preview_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_binding.dart';

void main() {
  const DevicePreviewToolbar config = DevicePreviewToolbar(
    appName: 'Kit Preview',
    initialDevice: DevicePresets.pixel10,
  );
  DevicePreviewBindingMixin.latchConfiguration(enabled: true, toolbar: config);
  final TestDevicePreviewBinding binding =
      TestDevicePreviewBinding.ensureInitializedWithoutLatching();
  final DevicePreviewController controller = binding.devicePreview!;

  tearDown(() => controller.applyPreset(DevicePresets.pixel10));

  /// Taps the center of [finder] with the host's mouse, in real physical
  /// coordinates — through the same pointer rewrite a real click takes.
  Future<void> click(WidgetTester tester, ui.Offset realLogical) async {
    final double ratio = tester.view.devicePixelRatio;
    for (final ui.PointerChange change in <ui.PointerChange>[
      ui.PointerChange.down,
      ui.PointerChange.up,
    ]) {
      binding.debugInjectPointerData(
        ui.PointerDataPacket(
          data: <ui.PointerData>[
            ui.PointerData(
              viewId: tester.view.viewId,
              change: change,
              kind: ui.PointerDeviceKind.mouse,
              device: 1,
              physicalX: realLogical.dx * ratio,
              physicalY: realLogical.dy * ratio,
              buttons: change == ui.PointerChange.down ? 1 : 0,
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Where [finder] is on the real window, in real logical pixels.
  ui.Offset onWindow(WidgetTester tester, Finder finder) {
    final RenderBox toolbar = tester.renderObject<RenderBox>(
      find.byType(DevicePreviewToolbarView),
    );
    final RenderBox target = tester.renderObject<RenderBox>(finder);
    return target.localToGlobal(
      target.size.center(ui.Offset.zero),
      ancestor: toolbar,
    );
  }

  Widget app(VoidCallback onPressed) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: ElevatedButton(onPressed: onPressed, child: const Text('app')),
      ),
    ),
  );

  testWidgets('starts on the initial device, below the bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(() {}));
    await tester.pumpAndSettle();

    expect(controller.simulation?.presetId, DevicePresets.pixel10.id);
    expect(find.text('Kit Preview'), findsOneWidget);
    expect(find.text(DevicePresets.pixel10.name), findsOneWidget);

    // The test window is 800 wide: the one-row bar, 56 tall. The fit leaves
    // the device body entirely below it.
    final FitTransform fit = controller.fitTransform;
    final ui.Rect body = controller.simulation!.contentBounds;
    expect(fit.toRealLogical(body.topLeft).dy, greaterThanOrEqualTo(56));
  });

  testWidgets('the platform switch moves to the first iOS device and back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(() {}));
    await tester.pumpAndSettle();

    await click(
      tester,
      onWindow(
        tester,
        find.byKey(const Key('device_preview_toolbar_platform_iOS')),
      ),
    );
    final String? iosId = controller.simulation?.presetId;
    final DevicePreset ios = controller.presets.firstWhere(
      (DevicePreset p) => p.id == iosId,
    );
    expect(ios.platform, TargetPlatform.iOS);

    await click(
      tester,
      onWindow(
        tester,
        find.byKey(const Key('device_preview_toolbar_platform_android')),
      ),
    );
    // Back to the Android device the bar was on, not the first one.
    expect(controller.simulation?.presetId, DevicePresets.pixel10.id);
  });

  testWidgets('the device menu applies the picked device', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(() {}));
    await tester.pumpAndSettle();

    await click(
      tester,
      onWindow(tester, find.byKey(const Key('device_preview_toolbar_devices'))),
    );
    final Finder item = find.byKey(
      Key('device_preview_toolbar_device_${DevicePresets.galaxyS25.id}'),
    );
    expect(item, findsOneWidget);
    // Android only: no iPhone, no desktop window.
    expect(
      find.byKey(
        Key('device_preview_toolbar_device_${DevicePresets.iPhone16.id}'),
      ),
      findsNothing,
    );
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await click(tester, onWindow(tester, item));
    expect(controller.simulation?.presetId, DevicePresets.galaxyS25.id);
  });

  testWidgets('rotate and brightness update the simulation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(() {}));
    await tester.pumpAndSettle();

    await click(
      tester,
      onWindow(tester, find.byKey(const Key('device_preview_toolbar_rotate'))),
    );
    expect(controller.simulation?.orientation, Orientation.landscape);

    final Brightness before =
        controller.simulation?.platformBrightness ??
        controller.realDevice.platformBrightness;
    await click(
      tester,
      onWindow(
        tester,
        find.byKey(const Key('device_preview_toolbar_brightness')),
      ),
    );
    expect(controller.simulation?.platformBrightness, isNot(before));
  });

  testWidgets('the app still takes taps on the simulated screen', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(app(() => taps++));
    await tester.pumpAndSettle();

    // The button's center, mapped from simulated to real logical pixels.
    final RenderBox button = tester.renderObject<RenderBox>(
      find.byType(ElevatedButton),
    );
    final ui.Offset simulated = button.localToGlobal(
      button.size.center(ui.Offset.zero),
      ancestor: tester.renderObject(find.byType(MaterialApp)),
    );
    await click(tester, controller.fitTransform.toRealLogical(simulated));
    expect(taps, 1);
  });

  testWidgets('a click outside the open menu closes it, not the app', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(app(() => taps++));
    await tester.pumpAndSettle();

    await click(
      tester,
      onWindow(tester, find.byKey(const Key('device_preview_toolbar_devices'))),
    );
    expect(find.byType(MenuItemButton), findsWidgets);

    final RenderBox button = tester.renderObject<RenderBox>(
      find.byType(ElevatedButton),
    );
    final ui.Offset simulated = button.localToGlobal(
      button.size.center(ui.Offset.zero),
      ancestor: tester.renderObject(find.byType(MaterialApp)),
    );
    await click(tester, controller.fitTransform.toRealLogical(simulated));
    expect(find.byType(MenuItemButton), findsNothing);
    expect(taps, 0);

    // Closed: the next click reaches the app again.
    await click(tester, controller.fitTransform.toRealLogical(simulated));
    expect(taps, 1);
  });

  test('offers Android and iOS handsets only, by default', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      final List<DevicePreset> offered = config.devicesFor(
        platform,
        DevicePresets.all,
      );
      expect(offered, isNotEmpty);
      for (final DevicePreset preset in offered) {
        expect(preset.platform, platform);
        expect(preset.kind, isNot(DeviceKind.desktop));
      }
    }
    expect(
      config.devicesFor(TargetPlatform.windows, DevicePresets.all),
      isEmpty,
      reason: 'desktop windows are never offered',
    );
  });
}
