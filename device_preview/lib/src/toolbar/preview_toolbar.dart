import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../presets.dart';
import '../controller/controller.dart';
import '../model/simulation.dart';

/// Configuration of the in-app toolbar, shown along the top of the real
/// window, above the simulated device.
///
/// 3.0 drives the simulation from DevTools, which a deployed build (a web
/// preview of an app, say) does not have. Passing a toolbar to
/// [DevicePreview.enable] gives the people viewing such a build a bar to
/// switch devices themselves:
///
/// ```dart
/// DevicePreview.enable(
///   enabled: true,
///   toolbar: const DevicePreviewToolbar(appName: 'My App'),
/// );
/// ```
///
/// The bar shows [appName], an Android / iOS switch, a device menu listing
/// the devices of the selected platform, and a light / dark button. It
/// deliberately has no switch to turn the preview off, and no rotate button:
/// the app always stays inside a device, in portrait.
///
/// Room for the bar is reserved when the device is fitted into the window,
/// so it never covers the app. It is only shown while a device is simulated;
/// when none is, the app fills the window as usual.
@immutable
class DevicePreviewToolbar {
  /// Creates a toolbar configuration.
  const DevicePreviewToolbar({
    this.appName,
    this.platforms = const <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ],
    this.devices,
    this.initialDevice,
    this.showBrightness = true,
    this.backgroundColor = const Color(0xFF18181C),
    this.accentColor = const Color(0xFF8AB4F8),
  });

  /// The name shown on the left of the bar. `Device Preview` when null.
  final String? appName;

  /// The platforms offered by the platform switch, in order.
  ///
  /// Android and iOS by default; desktop platforms are never offered unless
  /// listed here. Must not be empty.
  final List<TargetPlatform> platforms;

  /// The devices offered by the device menu, or null for every registered
  /// phone, tablet and foldable of the [platforms].
  final List<DevicePreset>? devices;

  /// The device shown on startup, or null for the first offered device.
  ///
  /// Ignored when a simulation is already active at startup.
  final DevicePreset? initialDevice;

  /// Whether the bar has a button to switch between light and dark.
  final bool showBrightness;

  /// The color of the bar.
  final Color backgroundColor;

  /// The color of the selected platform and device.
  final Color accentColor;

  /// Windows narrower than this stack the bar on two rows.
  static const double compactBreakpoint = 640;

  /// The height of the bar in a window of [realLogicalSize].
  static double heightFor(ui.Size realLogicalSize) =>
      realLogicalSize.width < compactBreakpoint ? 104 : 56;

  /// The devices offered for [platform], out of the controller's [presets].
  List<DevicePreset> devicesFor(
    TargetPlatform platform,
    List<DevicePreset> presets,
  ) {
    return <DevicePreset>[
      for (final DevicePreset preset in devices ?? presets)
        if (preset.platform == platform &&
            (devices != null || preset.kind != DeviceKind.desktop))
          preset,
    ];
  }

  /// The device to show on startup, out of the controller's [presets].
  DevicePreset? resolveInitialDevice(List<DevicePreset> presets) {
    if (initialDevice != null) {
      return initialDevice;
    }
    for (final TargetPlatform platform in platforms) {
      final List<DevicePreset> offered = devicesFor(platform, presets);
      if (offered.isNotEmpty) {
        return offered.first;
      }
    }
    return null;
  }
}

/// The toolbar widget: fills the real window, with the bar along its top.
///
/// Internal: built by the binding above the app, outside the app's own
/// `MaterialApp`, so it brings its own theme, localizations and overlay (the
/// device menu opens in it).
class DevicePreviewToolbarView extends StatefulWidget {
  /// Creates the toolbar for [controller].
  const DevicePreviewToolbarView({
    super.key,
    required this.config,
    required this.controller,
    required this.hostView,
  });

  /// What the bar offers.
  final DevicePreviewToolbar config;

  /// The controller the bar drives.
  final DevicePreviewController controller;

  /// The real (host) view: the toolbar lays out in real logical pixels, with
  /// the real text scale, whatever the simulation says.
  final ui.FlutterView hostView;

  @override
  State<DevicePreviewToolbarView> createState() =>
      _DevicePreviewToolbarViewState();
}

class _DevicePreviewToolbarViewState extends State<DevicePreviewToolbarView> {
  final MenuController _menu = MenuController();
  bool _menuOpen = false;

  /// The one entry of the toolbar's overlay, holding the bar; the device menu
  /// opens above it. Kept across builds: an [Overlay] reads its initial
  /// entries once, so state changes must rebuild the entry itself.
  late final OverlayEntry _bar = OverlayEntry(
    builder: (BuildContext context) =>
        ValueListenableBuilder<DeviceSimulation?>(
          valueListenable: _controller.simulationListenable,
          builder: _buildBar,
        ),
  );

  void _setMenuOpen(bool open) {
    if (_menuOpen != open) {
      _menuOpen = open;
      _bar.markNeedsBuild();
    }
  }

  /// The last device picked on each platform, so switching back returns to it.
  final Map<TargetPlatform, DevicePreset> _lastDevice =
      <TargetPlatform, DevicePreset>{};

  DevicePreviewController get _controller => widget.controller;

  DevicePreset? _presetOf(DeviceSimulation? simulation) {
    final String? id = simulation?.presetId;
    if (id == null) {
      return null;
    }
    for (final DevicePreset preset in _controller.presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  Future<void> _select(DevicePreset preset) async {
    _lastDevice[preset.platform] = preset;
    // Always portrait: the bar offers no rotation.
    await _controller.applyPreset(preset);
  }

  Future<void> _selectPlatform(TargetPlatform platform) async {
    final DevicePreset? remembered = _lastDevice[platform];
    final List<DevicePreset> offered = widget.config.devicesFor(
      platform,
      _controller.presets,
    );
    final DevicePreset? next =
        remembered ?? (offered.isEmpty ? null : offered.first);
    if (next != null) {
      await _select(next);
    }
  }

  Future<void> _toggleBrightness(Brightness current) {
    return _controller.update(
      (DeviceSimulation s) => s.copyWith(
        platformBrightness: current == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DevicePreviewToolbar config = widget.config;
    final ThemeData theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: config.accentColor,
        brightness: Brightness.dark,
        primary: config.accentColor,
      ),
    );
    // Laid out at the real window's size by the chrome, so the constraints
    // are the window: a host resize rebuilds through the LayoutBuilder.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => MediaQuery(
        data: MediaQueryData.fromView(
          widget.hostView,
        ).copyWith(size: constraints.biggest),
        child: _themed(theme),
      ),
    );
  }

  Widget _themed(ThemeData theme) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: const <LocalizationsDelegate<Object?>>[
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Theme(
          data: theme,
          child: Shortcuts(
            shortcuts: WidgetsApp.defaultShortcuts,
            child: Actions(
              actions: WidgetsApp.defaultActions,
              child: TapRegionSurface(
                child: Overlay(initialEntries: <OverlayEntry>[_bar]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(
    BuildContext context,
    DeviceSimulation? simulation,
    Widget? child,
  ) {
    final DevicePreviewToolbar config = widget.config;
    final ui.Size window = MediaQuery.sizeOf(context);
    final bool compact = window.width < DevicePreviewToolbar.compactBreakpoint;
    final DevicePreset? current = _presetOf(simulation);
    if (current != null) {
      _lastDevice[current.platform] = current;
    }
    final TargetPlatform platform = current?.platform ?? config.platforms.first;
    final Brightness brightness =
        simulation?.platformBrightness ??
        _controller.realDevice.platformBrightness;

    final Widget title = Text(
      config.appName ?? 'Device Preview',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
    final List<Widget> actions = <Widget>[
      if (config.showBrightness)
        IconButton(
          key: const Key('device_preview_toolbar_brightness'),
          tooltip: brightness == Brightness.dark ? 'Light mode' : 'Dark mode',
          icon: Icon(
            brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
          onPressed: () => _toggleBrightness(brightness),
        ),
    ];
    final Widget platforms = _PlatformSwitch(
      platforms: config.platforms,
      selected: platform,
      accentColor: config.accentColor,
      onSelected: _selectPlatform,
    );
    final Widget devices = _deviceMenu(platform, current);

    final Widget bar = compact
        ? Column(
            children: <Widget>[
              SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 16),
                    Expanded(child: title),
                    ...actions,
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: <Widget>[
                      platforms,
                      const SizedBox(width: 8),
                      Expanded(child: devices),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Row(
            children: <Widget>[
              const SizedBox(width: 20),
              Expanded(child: title),
              platforms,
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: devices,
              ),
              const SizedBox(width: 8),
              ...actions,
              const SizedBox(width: 8),
            ],
          );

    return Stack(
      children: <Widget>[
        // While the menu is open, a tap anywhere closes it — and stays out of
        // the app, as it would with a menu of the app's own. Always in the
        // tree: adding it would rebuild the bar, and close the menu with it.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_menuOpen,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Positioned(
          left: 0,
          // Below the host's own status bar, where the fit reserved the room.
          top: MediaQuery.paddingOf(context).top,
          right: 0,
          height: DevicePreviewToolbar.heightFor(window),
          child: Material(
            color: config.backgroundColor,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2E2E34))),
              ),
              child: bar,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceMenu(TargetPlatform platform, DevicePreset? current) {
    final DevicePreviewToolbar config = widget.config;
    final List<DevicePreset> offered = config.devicesFor(
      platform,
      _controller.presets,
    );
    final List<Widget> items = <Widget>[];
    for (final DeviceKind kind in DeviceKind.values) {
      final List<DevicePreset> group = <DevicePreset>[
        for (final DevicePreset preset in offered)
          if (preset.kind == kind) preset,
      ];
      if (group.isEmpty) {
        continue;
      }
      items.add(_MenuHeader(label: _kindLabel(kind)));
      for (final DevicePreset preset in group) {
        final bool selected = preset.id == current?.id;
        items.add(
          MenuItemButton(
            key: Key('device_preview_toolbar_device_${preset.id}'),
            leadingIcon: Icon(
              Icons.check,
              size: 18,
              color: selected ? config.accentColor : Colors.transparent,
            ),
            onPressed: () => _select(preset),
            child: Text(preset.name),
          ),
        );
      }
    }
    return MenuAnchor(
      controller: _menu,
      menuChildren: items,
      onOpen: () => _setMenuOpen(true),
      onClose: () => _setMenuOpen(false),
      builder: (BuildContext context, MenuController menu, Widget? child) {
        return OutlinedButton(
          key: const Key('device_preview_toolbar_devices'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF3A3A40)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: offered.isEmpty
              ? null
              : () => menu.isOpen ? menu.close() : menu.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  current?.name ?? 'Choose a device',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        );
      },
    );
  }

  static String _kindLabel(DeviceKind kind) => switch (kind) {
    DeviceKind.phone => 'Phones',
    DeviceKind.tablet => 'Tablets',
    DeviceKind.foldable => 'Foldables',
    DeviceKind.desktop => 'Desktop',
  };
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF9A9AA2),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PlatformSwitch extends StatelessWidget {
  const _PlatformSwitch({
    required this.platforms,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
  });

  final List<TargetPlatform> platforms;
  final TargetPlatform selected;
  final Color accentColor;
  final ValueChanged<TargetPlatform> onSelected;

  static String _label(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };

  static IconData _icon(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => Icons.android,
    TargetPlatform.iOS || TargetPlatform.macOS => Icons.apple,
    _ => Icons.desktop_windows_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF26262B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final TargetPlatform platform in platforms)
            _PlatformButton(
              key: Key('device_preview_toolbar_platform_${platform.name}'),
              label: _label(platform),
              icon: _icon(platform),
              selected: platform == selected,
              accentColor: accentColor,
              onTap: () => onSelected(platform),
            ),
        ],
      ),
    );
  }
}

class _PlatformButton extends StatelessWidget {
  const _PlatformButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? const Color(0xFF111114)
        : const Color(0xFFC8C8CE);
    return Material(
      color: selected ? accentColor : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
