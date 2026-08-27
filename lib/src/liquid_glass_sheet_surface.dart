import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shares/liquid_glass_config.dart';
import 'utils/liquid_glass_route_suppression.dart';
import 'utils/native_liquid_glass_utils.dart';

/// A full-bleed Liquid Glass *surface*, for backgrounds rather than floating
/// objects.
///
/// [LiquidGlassContainer] renders SwiftUI's `Glass.regular`/`Glass.clear` via
/// `.glassEffect(_:in: shape)` — the API Apple designed for discrete floating
/// controls (buttons, pills, chips). That API always ships with a specular
/// edge highlight so the element reads as a glass object sitting on top of
/// content; there is no flag to turn it off.
///
/// Full-screen backgrounds aren't supposed to look like objects — a real
/// `UISheetPresentationController`'s own material, and UIKit's
/// `UINavigationBar`/`UIToolbar` glass, render with no border at all. This
/// widget reproduces that "surface" look for arbitrary Flutter content by
/// applying `UIGlassEffect` through a plain `UIVisualEffectView` on the
/// native side — the raw material UIKit itself uses for bars — instead of
/// SwiftUI's decorated object API.
///
/// Use this instead of [LiquidGlassContainer] for bottom sheets, full-screen
/// panels, and other backgrounds where a bright edge highlight would look
/// out of place. Keep using [LiquidGlassContainer] for buttons/pills/chips,
/// where that highlight is the correct, expected look.
///
/// Only [LiquidGlassConfig.effect], [LiquidGlassConfig.cornerRadius],
/// [LiquidGlassConfig.tint], and [LiquidGlassConfig.backgroundColor] apply
/// here — [LiquidGlassConfig.shape], [LiquidGlassConfig.border],
/// [LiquidGlassConfig.interactive], [LiquidGlassConfig.customPath], and the
/// glass-effect-union fields are ignored (they only make sense for the
/// object-style API).
class LiquidGlassSheetSurface extends StatefulWidget {
  /// The widget to render on top of the glass surface.
  final Widget child;

  /// Glass effect configuration. Only [LiquidGlassConfig.effect],
  /// [LiquidGlassConfig.cornerRadius], [LiquidGlassConfig.tint], and
  /// [LiquidGlassConfig.backgroundColor] are read.
  final LiquidGlassConfig config;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// When true, config changes animate on the native side instead of
  /// snapping instantly.
  final bool animateChanges;

  const LiquidGlassSheetSurface({
    super.key,
    required this.child,
    this.config = const LiquidGlassConfig(),
    this.width,
    this.height,
    this.animateChanges = false,
  });

  @override
  State<LiquidGlassSheetSurface> createState() =>
      _LiquidGlassSheetSurfaceState();
}

class _LiquidGlassSheetSurfaceState extends State<LiquidGlassSheetSurface>
    with LiquidGlassRouteSuppression {
  MethodChannel? _nativeChannel;

  @override
  MethodChannel? get suppressionChannel => _nativeChannel;

  String? _lastEffect;
  double? _lastCornerRadius;
  int? _lastTint;
  int? _lastBackgroundColor;

  Map<String, Object?> _creationParams() => {
        'effect': widget.config.effect.name,
        'cornerRadius': widget.config.cornerRadius,
        'tint': widget.config.tint?.toARGB32(),
        'backgroundColor': widget.config.backgroundColor?.toARGB32(),
      };

  @override
  void didUpdateWidget(covariant LiquidGlassSheetSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void reassemble() {
    super.reassemble();
    _lastEffect = null;
    _syncPropsToNativeIfNeeded();
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _nativeChannel;
    if (ch == null) return;

    final effect = widget.config.effect.name;
    final cornerRadius = widget.config.cornerRadius;
    final tint = widget.config.tint?.toARGB32();
    final backgroundColor = widget.config.backgroundColor?.toARGB32();

    if (_lastEffect != effect ||
        _lastCornerRadius != cornerRadius ||
        _lastTint != tint ||
        _lastBackgroundColor != backgroundColor) {
      await ch.invokeMethod('updateConfig', {
        ..._creationParams(),
        'animated': widget.animateChanges,
      });
      _lastEffect = effect;
      _lastCornerRadius = cornerRadius;
      _lastTint = tint;
      _lastBackgroundColor = backgroundColor;
    }
  }

  void _onPlatformViewCreated(int viewId) {
    _nativeChannel?.setMethodCallHandler(null);
    final channel = MethodChannel('liquid-glass-sheet-surface-view/$viewId');
    _nativeChannel = channel;
    _lastEffect = widget.config.effect.name;
    _lastCornerRadius = widget.config.cornerRadius;
    _lastTint = widget.config.tint?.toARGB32();
    _lastBackgroundColor = widget.config.backgroundColor?.toARGB32();
    syncGlassRouteVisibility();
  }

  @override
  void dispose() {
    _nativeChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeLiquidGlassUtils.supportsLiquidGlass) {
      return SizedBox(width: widget.width, height: widget.height, child: widget.child);
    }

    final nativeView = UiKitView(
      viewType: 'liquid-glass-sheet-surface-view',
      creationParams: _creationParams(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: nativeView)),
          widget.child,
        ],
      ),
    );
  }
}
