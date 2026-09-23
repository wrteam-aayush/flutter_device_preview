// A web preview with the in-app toolbar: what a deployed preview of an app
// (a UI kit's showcase, say) looks like when there is no DevTools to drive
// the simulation.
//
//   flutter run -d chrome -t lib/web_preview.dart
//   flutter build web -t lib/web_preview.dart
//
// The toolbar carries the app's name, an Android / iOS switch, a device menu,
// and rotate and light / dark buttons. There is no switch to turn the
// preview off, and dragging with the mouse scrolls like a finger.

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/material.dart';

import 'todo.dart' show TodoApp;

void main() {
  DevicePreview.enable(
    // `true` rather than the default: a deployed web preview is a *release*
    // build, where simulation would otherwise be off.
    enabled: true,
    padding: const EdgeInsets.all(16),
    toolbar: const DevicePreviewToolbar(
      appName: 'Todo Kit',
      initialDevice: DevicePresets.iPhone16Pro,
    ),
  );
  runApp(const TodoApp());
}
