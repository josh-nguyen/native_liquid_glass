import Flutter
import UIKit

/// Platform-view bridge for a *raw* Liquid Glass material, applied as a
/// full-bleed background rather than a discrete glass "object".
///
/// `LiquidGlassContainer` (see `LiquidGlassContainer/`) renders SwiftUI's
/// `Glass.regular`/`Glass.clear` via `.glassEffect(_:in: shape)`. That API is
/// designed for floating controls — buttons, pills, chips — and Apple bakes
/// in a specular edge highlight so the element visually reads as a discrete
/// glass object sitting on top of content. There is no public flag to turn
/// that highlight off; it ships unconditionally with every shape-based
/// `glassEffect`.
///
/// Full-screen surfaces that are supposed to *be* the background — system
/// sheets, navigation bars, toolbars — don't get that treatment. UIKit's own
/// `UINavigationBar`/`UIToolbar` render Liquid Glass automatically with no
/// border, and a real `UISheetPresentationController`'s backing material has
/// none either (see the reference in the PR description: a `.sheet()` with
/// `.scrollContentBackground(.hidden)` shows this borderless variant).
///
/// This view reproduces that "surface" look for arbitrary Flutter content by
/// applying `UIGlassEffect` directly via a plain `UIVisualEffectView` — the
/// raw material UIKit itself uses for bars — instead of SwiftUI's decorated
/// object API. No border, no specular rim.
final class LiquidGlassSheetSurfacePlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let methodChannel: FlutterMethodChannel
  private var suppressObserver: GlassSuppressObserver?

  /// `nil` on pre-iOS 26 (or when the glass effect view couldn't be
  /// created); the container then stays a plain clear `UIView`.
  private var effectView: UIVisualEffectView?
  private var backgroundFillView: UIView?

  init(
    frame: CGRect,
    viewId: Int64,
    arguments args: [String: Any]?,
    messenger: FlutterBinaryMessenger
  ) {
    containerView = UIView(frame: frame)
    containerView.backgroundColor = .clear

    methodChannel = FlutterMethodChannel(
      name: "liquid-glass-sheet-surface-view/\(viewId)",
      binaryMessenger: messenger
    )

    super.init()
    suppressObserver = GlassSuppressObserver(view: containerView)

    setupGlassView(args: args)
    setupMethodChannelHandler()
  }

  func view() -> UIView {
    containerView
  }

  // MARK: - Setup (called once)

  private func setupGlassView(args: [String: Any]?) {
    guard #available(iOS 26.0, *) else { return }

    let bgView = UIView()
    bgView.translatesAutoresizingMaskIntoConstraints = false
    bgView.backgroundColor = Self.decodeColor(from: args?["backgroundColor"])

    let effectView = UIVisualEffectView(effect: Self.makeGlassEffect(from: args))
    effectView.translatesAutoresizingMaskIntoConstraints = false

    containerView.addSubview(bgView)
    containerView.addSubview(effectView)
    NSLayoutConstraint.activate([
      bgView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      bgView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      bgView.topAnchor.constraint(equalTo: containerView.topAnchor),
      bgView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      effectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      effectView.topAnchor.constraint(equalTo: containerView.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])

    applyCornerRadius(from: args, to: containerView)

    self.effectView = effectView
    self.backgroundFillView = bgView
  }

  // MARK: - Update (called on config changes)

  private func updateGlassView(args: [String: Any]?, animated: Bool) {
    guard #available(iOS 26.0, *), let effectView else { return }
    let apply = {
      effectView.effect = Self.makeGlassEffect(from: args)
      self.backgroundFillView?.backgroundColor = Self.decodeColor(from: args?["backgroundColor"])
      self.applyCornerRadius(from: args, to: self.containerView)
    }
    if animated {
      UIView.animate(withDuration: 0.3, animations: apply)
    } else {
      apply()
    }
  }

  private func applyCornerRadius(from args: [String: Any]?, to view: UIView) {
    let cornerRadius = (args?["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    view.layer.cornerRadius = cornerRadius
    view.clipsToBounds = cornerRadius > 0
  }

  @available(iOS 26.0, *)
  private static func makeGlassEffect(from args: [String: Any]?) -> UIGlassEffect {
    let styleRaw = args?["effect"] as? String
    let glass = UIGlassEffect(style: styleRaw == "clear" ? .clear : .regular)
    glass.tintColor = decodeColor(from: args?["tint"])
    return glass
  }

  // MARK: - Method Channel

  private func setupMethodChannelHandler() {
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }

      switch call.method {
      case "updateConfig":
        let args = call.arguments as? [String: Any]
        let animated = (args?["animated"] as? Bool) ?? false
        self.updateGlassView(args: args, animated: animated)
        result(nil)

      case "setSuppressed":
        let suppressed = (call.arguments as? [String: Any])?["suppressed"] as? Bool ?? false
        self.suppressObserver?.setRouteSuppressed(suppressed)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func decodeColor(from value: Any?) -> UIColor? {
    guard let numericValue = value as? NSNumber else { return nil }
    let argb = UInt32(bitPattern: Int32(truncatingIfNeeded: numericValue.intValue))
    let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
    let red = CGFloat((argb >> 16) & 0xFF) / 255.0
    let green = CGFloat((argb >> 8) & 0xFF) / 255.0
    let blue = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
