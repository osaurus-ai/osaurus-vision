import Foundation
import Testing

/// Vision/CoreML analysis requests block indefinitely on virtualized CI
/// runners (no GPU/ANE available to the guest), so any test that reaches a
/// real `VNImageRequestHandler.perform` is skipped when `CI` is set in the
/// environment. Validation, manifest, and envelope tests still run on CI.
///
/// Set `OSAURUS_VISION_RUNTIME_TESTS=1` to force-run the gated tests (for
/// local runs this is unnecessary — they run whenever `CI` is unset).
enum VisionRuntime {
  static let available: Bool = {
    let env = ProcessInfo.processInfo.environment
    if env["OSAURUS_VISION_RUNTIME_TESTS"] == "1" { return true }
    return env["CI"] == nil
  }()

  static let required: ConditionTrait = .enabled(
    if: available,
    "Vision/CoreML requests hang on virtualized CI runners without GPU/ANE")
}
