# Device Preview 3.0 migration for UI8 Flutter Kit previews

Our fork now runs Device Preview 3.0 on the `release/v3` branch. Moving a kit takes three small edits and about 10 minutes. The `v1.3.1` branch is unchanged, so kits you haven't migrated keep working.

## Step 1: Update pubspec.yaml

Point `device_preview` at the new branch. You need Flutter 3.47 or newer.

```yaml
dependencies:
  device_preview:
    git:
      url: https://github.com/wrteam-aayush/flutter_device_preview.git
      ref: release/v3
      path: device_preview
```

If the kit also depends on `device_frame`, remove it. Frames are now built into `device_preview`. Then run `flutter pub upgrade device_preview`.

## Step 2: Replace the wrapper in main.dart

The `DevicePreview(builder: ...)` widget is gone. Call `DevicePreview.enable()` before `runApp`, and pass the app name to the toolbar.

Before (v1.3.1):

```dart
void main() {
  runApp(
    DevicePreview(
      enabled: kIsWeb,
      appName: 'Kit Name',
      builder: (context) => const MyApp(),
    ),
  );
}
```

After (release/v3):

```dart
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';

void main() {
  DevicePreview.enable(
    enabled: kIsWeb, // web: device preview; Android / iOS: normal app
    toolbar: const DevicePreviewToolbar(appName: 'Kit Name'),
  );
  runApp(const MyApp());
}
```

### Web only: `enabled: kIsWeb`

Always pass `enabled: kIsWeb`. This keeps device preview on the web build only:

| Platform | What runs |
| --- | --- |
| Web (the UI8 preview link) | The app inside a device frame, with the toolbar |
| Android and iOS | The normal app, full screen, with no device preview at all |

`kIsWeb` comes from `package:flutter/foundation.dart`, so keep that import. Don't leave `enabled:` out: the default turns the preview off in release builds, which is what we deploy to the web.

Optional toolbar settings:

| Setting | Default | Use it to |
| --- | --- | --- |
| `appName` | `Device Preview` | Show the kit's name on the left of the bar |
| `initialDevice` | First Android phone | Open on a device, e.g. `DevicePresets.iPhone16Pro` (import `package:device_preview/presets.dart`) |
| `devices` | All Android and iOS phones, tablets and foldables | Offer a shorter device list |
| `showBrightness` | `true` | Hide the light / dark button |

## Step 3: Remove the Device Preview lines from MaterialApp

Delete these three lines. 3.0 simulates the device below the widget layer, so the app no longer needs them.

```dart
MaterialApp(
  useInheritedMediaQuery: true,          // delete
  locale: DevicePreview.locale(context), // delete
  builder: DevicePreview.appBuilder,     // delete
  ...
)
```

If `builder:` also wrapped something of your own, keep your wrapper and drop only `DevicePreview.appBuilder`. Then do a full restart (not hot reload) and run `flutter build web`.

## What buyers will see

- **Bar along the top:** the kit name, an Android / iOS switch, a device menu, and a light / dark button.
- **Portrait only:** there is no rotate button, since all our apps are portrait.
- **No on/off switch:** buyers can't turn the preview off, so the app always stays inside a device.
- **Android and iOS only:** Windows, macOS and Linux windows are no longer offered.
- **Drag to scroll:** clicking and dragging with the mouse scrolls lists like a finger. The mouse wheel still works too.
- **Real device frames:** status bar, notch or Dynamic Island, and home indicator, for current iPhone, iPad, Pixel and Galaxy models.

To see a working example, run `flutter run -d chrome -t lib/web_preview.dart` in `device_preview/example` on the `release/v3` branch. Questions go to Aayush.
