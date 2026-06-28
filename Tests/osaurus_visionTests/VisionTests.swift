import Foundation
import Testing

@testable import osaurus_vision

// MARK: - Manifest Unit Tests

@Suite("Manifest Contract")
struct ManifestContractTests {

  /// Parses the embedded manifest directly (no dylib) and validates the host contract.
  private func parsedManifest() throws -> [String: Any] {
    let data = try #require(visionManifestJSON.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
  }

  @Test("Manifest is valid JSON with expected identity")
  func testManifestIdentity() throws {
    let manifest = try parsedManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.vision")
    #expect(manifest["name"] as? String == "Vision")
  }

  @Test("Every tool declares a non-empty id and description")
  func testToolsHaveIdAndDescription() throws {
    let manifest = try parsedManifest()
    let capabilities = try #require(manifest["capabilities"] as? [String: Any])
    let tools = try #require(capabilities["tools"] as? [[String: Any]])

    #expect(tools.count == 15)

    for tool in tools {
      let id = tool["id"] as? String
      let description = tool["description"] as? String
      #expect(id?.isEmpty == false, "tool is missing a non-empty id: \(tool)")
      #expect(description?.isEmpty == false, "tool \(id ?? "?") is missing a non-empty description")
    }

    // All ids must be unique.
    let ids = tools.compactMap { $0["id"] as? String }
    #expect(Set(ids).count == ids.count)
  }
}

// MARK: - Envelope Unit Tests

@Suite("Envelope")
struct EnvelopeTests {

  private func parse(_ json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
  }

  @Test("failure round-trips to a well-formed envelope with default retryable")
  func testFailureDefaults() throws {
    let cases: [(Envelope.Kind, String, Bool)] = [
      (.invalidArgs, "invalid_args", true),
      (.executionError, "execution_error", true),
      (.unavailable, "unavailable", true),
      (.notFound, "not_found", false),
    ]

    for (kind, rawKind, expectedRetryable) in cases {
      let envelope = try parse(Envelope.failure(kind, "boom"))
      #expect(envelope["ok"] as? Bool == false)
      #expect(envelope["kind"] as? String == rawKind)
      #expect(envelope["message"] as? String == "boom")
      #expect(envelope["retryable"] as? Bool == expectedRetryable)
    }
  }

  @Test("failure honors an explicit retryable override")
  func testFailureRetryableOverride() throws {
    let envelope = try parse(Envelope.failure(.notFound, "missing", retryable: true))
    #expect(envelope["retryable"] as? Bool == true)
    #expect(envelope["kind"] as? String == "not_found")
  }

  @Test("failure escapes control characters and quotes in the message")
  func testFailureEscapesMessage() throws {
    let tricky = "line1\nline2\t\"quoted\" \\slash\\"
    let envelope = try parse(Envelope.failure(.executionError, tricky))
    #expect(envelope["message"] as? String == tricky)
  }

  @Test("successRaw wraps a payload without altering it")
  func testSuccessRaw() throws {
    let envelope = try parse(Envelope.successRaw("{\"value\":42}"))
    #expect(envelope["ok"] as? Bool == true)
    let result = try #require(envelope["result"] as? [String: Any])
    #expect(result["value"] as? Int == 42)
  }
}
