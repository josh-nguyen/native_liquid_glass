import UIKit

/// SwiftUI's `Glass.regular`/`Glass.clear` — the API behind every
/// `UIHostingController`-backed Liquid Glass view in this plugin (buttons,
/// search bars, toggles, sliders, segmented control, toolbars, button
/// groups, the container) — needs a couple of render passes on a brand new
/// `UIHostingController` to settle its live backdrop sampling. Until it
/// does, the first frames can paint a visibly wrong intermediate state: a
/// brief shimmer/flash on the very first appearance of each fresh instance.
/// Subsequent appearances of the *same* instance never show it again, since
/// the backdrop sampling is already settled.
///
/// `UIVisualEffectView`/`UIGlassEffect` (the plain UIKit path used by
/// `LiquidGlassSheetSurface`) doesn't have this problem — it's a much
/// older, already-optimized rendering path with no comparable warm-up. This
/// only affects views hosted through SwiftUI's `Glass` API.
///
/// Rather than let that unsettled state be visible, call this right after
/// creating a hosting controller's view (before adding it to the
/// hierarchy) to hide it briefly, then reveal it once the material has had
/// time to settle. No animation on reveal — a fade-in would itself read as
/// a shimmer, just a smoother one; snapping straight to the settled state
/// is what looks like nothing happened at all.
extension UIView {
  func maskGlassColdStart() {
    alpha = 0
    // ponytail: fixed 50ms delay, not a real "settled" signal from SwiftUI
    // (there isn't a public one). Comfortably covers the couple of frames
    // Glass needs even at 120Hz ProMotion, chosen empirically rather than
    // measured. Revisit if a future SDK exposes a real readiness callback.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.alpha = 1
    }
  }
}
