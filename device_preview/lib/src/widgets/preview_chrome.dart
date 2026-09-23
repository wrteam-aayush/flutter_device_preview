import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/fit_transform.dart';
import '../model/simulation.dart';

/// The two children of a [PreviewChrome].
enum PreviewChromeSlot {
  /// The app, laid out and painted in simulated logical coordinates.
  app,

  /// The in-app toolbar, laid out and painted in real logical coordinates.
  toolbar,
}

/// Lays [toolbar] over the whole real window, above [app].
///
/// Internal: the binding wraps the app with it when `DevicePreview.enable`
/// is given a `toolbar`; it is never exported.
///
/// Like `PreviewBackground`, this render object lives in *simulated* logical
/// coordinates — the root view configuration scales everything it paints by
/// the fit transform — and undoes the fit for the toolbar, which is then laid
/// out at the real window's logical size and painted 1:1 on screen whatever
/// the simulated device.
///
/// The toolbar sits in the letterbox, outside the simulated screen, where the
/// app's render boxes reject every hit test. The binding therefore asks
/// [RenderPreviewChrome.hitTestToolbar] first, before hit testing the app.
///
/// Nothing is painted or hit while no metric simulation is active: the app
/// then fills the window and there is no letterbox to host the toolbar.
class PreviewChrome
    extends SlottedMultiChildRenderObjectWidget<PreviewChromeSlot, RenderBox> {
  /// Places [toolbar] over the real window, above [app].
  const PreviewChrome({
    super.key,
    required this.app,
    required this.toolbar,
    required this.simulation,
    required this.fit,
    required this.hostView,
  });

  /// The app, wrapped in the frame and background.
  final Widget app;

  /// The toolbar, expected to fill the real window and be transparent to hit
  /// tests outside its own bars.
  final Widget toolbar;

  /// The live simulation; decides whether the toolbar is shown.
  final ValueListenable<DeviceSimulation?> simulation;

  /// The live scale-to-fit mapping.
  final ValueListenable<FitTransform> fit;

  /// The real (host) view, read live for the window's logical size.
  final ui.FlutterView hostView;

  @override
  Iterable<PreviewChromeSlot> get slots => PreviewChromeSlot.values;

  @override
  Widget? childForSlot(PreviewChromeSlot slot) => switch (slot) {
    PreviewChromeSlot.app => app,
    PreviewChromeSlot.toolbar => toolbar,
  };

  @override
  RenderPreviewChrome createRenderObject(BuildContext context) =>
      RenderPreviewChrome(simulation: simulation, fit: fit, hostView: hostView);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPreviewChrome renderObject,
  ) {
    renderObject
      ..simulation = simulation
      ..fit = fit
      ..hostView = hostView;
  }
}

/// The render object behind [PreviewChrome].
class RenderPreviewChrome extends RenderBox
    with SlottedContainerRenderObjectMixin<PreviewChromeSlot, RenderBox> {
  /// Creates the render object.
  RenderPreviewChrome({
    required ValueListenable<DeviceSimulation?> simulation,
    required ValueListenable<FitTransform> fit,
    required ui.FlutterView hostView,
  }) : _simulation = simulation,
       _fit = fit,
       _hostView = hostView;

  ValueListenable<DeviceSimulation?> _simulation;

  /// The live simulation.
  ValueListenable<DeviceSimulation?> get simulation => _simulation;
  set simulation(ValueListenable<DeviceSimulation?> value) {
    if (identical(value, _simulation)) {
      return;
    }
    if (attached) {
      _simulation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _simulation = value;
    markNeedsPaint();
  }

  ValueListenable<FitTransform> _fit;

  /// The live scale-to-fit mapping. A change relayouts the toolbar: the fit
  /// moves whenever the real window is resized.
  ValueListenable<FitTransform> get fit => _fit;
  set fit(ValueListenable<FitTransform> value) {
    if (identical(value, _fit)) {
      return;
    }
    if (attached) {
      _fit.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _fit = value;
    markNeedsLayout();
  }

  ui.FlutterView _hostView;

  /// The real (host) view.
  ui.FlutterView get hostView => _hostView;
  set hostView(ui.FlutterView value) {
    if (identical(value, _hostView)) {
      return;
    }
    _hostView = value;
    markNeedsLayout();
  }

  RenderBox? get _app => childForSlot(PreviewChromeSlot.app);
  RenderBox? get _toolbar => childForSlot(PreviewChromeSlot.toolbar);

  /// Whether the toolbar is shown: only around a metric simulation.
  bool get _showsToolbar {
    final DeviceSimulation? active = _simulation.value;
    return active != null && active.simulatesMetrics && _fit.value.scale > 0;
  }

  /// Maps the toolbar's real logical coordinates into this box's simulated
  /// logical ones.
  Matrix4 get _toolbarTransform {
    final FitTransform fit = _fit.value;
    final Offset origin = fit.toSimulatedLogical(Offset.zero);
    return Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(1 / fit.scale, 1 / fit.scale, 1, 1);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _simulation.addListener(markNeedsPaint);
    _fit.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _simulation.removeListener(markNeedsPaint);
    _fit.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    final RenderBox? app = _app;
    if (app != null) {
      app.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(app.size);
    } else {
      size = constraints.biggest;
    }
    final ui.Size real = _hostView.physicalSize / _hostView.devicePixelRatio;
    _toolbar?.layout(BoxConstraints.tight(real));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? app = _app;
    if (app != null) {
      context.paintChild(app, offset);
    }
    final RenderBox? toolbar = _toolbar;
    if (toolbar != null && _showsToolbar) {
      context.pushTransform(
        needsCompositing,
        offset,
        _toolbarTransform,
        (PaintingContext context, Offset offset) =>
            context.paintChild(toolbar, offset),
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _toolbar)) {
      transform.multiply(_toolbarTransform);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return _app?.hitTest(result, position: position) ?? false;
  }

  /// Hit tests the toolbar at [position], in this box's (simulated logical)
  /// coordinates. True when one of the toolbar's widgets was hit, in which
  /// case the app must not be hit tested at all.
  bool hitTestToolbar(BoxHitTestResult result, Offset position) {
    final RenderBox? toolbar = _toolbar;
    if (toolbar == null || !toolbar.hasSize || !_showsToolbar) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _toolbarTransform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          toolbar.hitTest(result, position: position),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _app?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _app?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _app?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _app?.getMaxIntrinsicHeight(width) ?? 0;
}
