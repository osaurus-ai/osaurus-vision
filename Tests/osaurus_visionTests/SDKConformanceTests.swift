import Foundation
import OsaurusPluginABI
import OsaurusPluginTestSupport
import Testing

@testable import osaurus_vision

/// SDK conformance checks: manifest contract, ABI entry-point contract
/// (via the plugin's real exported entry points), and the canonical
/// failure envelope emitted by a real tool invocation.
@Suite("SDK Conformance")
struct SDKConformanceTests {

  @Test("Manifest conforms to the registry contract")
  func testManifestConformance() throws {
    try ManifestConformance.assertConformant(visionManifestJSON)
  }

  @Test("osaurus_plugin_entry_v2 returns a conformant API table")
  func testEntryV2Conformance() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry_v2(nil), manifestJSON: visionManifestJSON)
  }

  @Test("osaurus_plugin_entry returns a conformant API table")
  func testEntryV1Conformance() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry(), manifestJSON: visionManifestJSON)
  }

  @Test("Tool failures use the canonical failure envelope")
  func testToolFailureIsCanonical() throws {
    let entry = try #require(osaurus_plugin_entry_v2(nil))
    let api = entry.assumingMemoryBound(to: OsrPluginAPI.self).pointee
    let ctx = try #require(api.`init`?())
    defer { api.destroy?(ctx) }

    let resultPtr = try #require(api.invoke?(ctx, "tool", "detect_text", "not json"))
    let json = String(cString: resultPtr)
    api.free_string?(resultPtr)

    try assertCanonicalFailure(json, kind: .invalidArgs)
  }
}
