import AppKit
import Foundation
import Testing

// MARK: - Reliability regression tests (path safety, validation, output encoding)

@Suite("Path Containment Tests", .serialized)
struct PathContainmentTests {

  @Test("Sibling directory sharing the working-directory prefix is rejected")
  func testSiblingPrefixEscape() throws {
    try TestImageGenerator.setup()
    let base = TestImageGenerator.tempDir.appendingPathComponent("escape-\(UUID().uuidString)")
    let workDir = base.appendingPathComponent("project")
    let evilDir = base.appendingPathComponent("project-evil")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: evilDir, withIntermediateDirectories: true)
    let image = try TestImageGenerator.createColorImage()
    try FileManager.default.copyItem(at: image, to: evilDir.appendingPathComponent("img.png"))

    let result = PluginInvoker.shared.invoke(
      tool: "detect_faces",
      args: [
        "image_path": "../project-evil/img.png",
        "_context": ["working_directory": workDir.path],
      ])

    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
    #expect((result["message"] as? String)?.contains("outside working directory") == true)
  }

  @Test("Symlink pointing outside the working directory is rejected")
  func testSymlinkEscape() throws {
    try TestImageGenerator.setup()
    let base = TestImageGenerator.tempDir.appendingPathComponent("symlink-\(UUID().uuidString)")
    let workDir = base.appendingPathComponent("work")
    let outsideDir = base.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    let image = try TestImageGenerator.createColorImage()
    try FileManager.default.copyItem(at: image, to: outsideDir.appendingPathComponent("secret.png"))
    try FileManager.default.createSymbolicLink(
      at: workDir.appendingPathComponent("link"), withDestinationURL: outsideDir)

    let result = PluginInvoker.shared.invoke(
      tool: "detect_faces",
      args: [
        "image_path": "link/secret.png",
        "_context": ["working_directory": workDir.path],
      ])

    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
  }

  // blur_faces runs face detection before output-path validation, so this
  // reaches Vision and must be gated on CI.
  @Test("Symlink escape is rejected for output paths too", VisionRuntime.required)
  func testSymlinkEscapeOnOutputPath() throws {
    try TestImageGenerator.setup()
    let base = TestImageGenerator.tempDir.appendingPathComponent("symout-\(UUID().uuidString)")
    let workDir = base.appendingPathComponent("work")
    let outsideDir = base.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    let image = try TestImageGenerator.createFaceImage()
    try FileManager.default.copyItem(at: image, to: workDir.appendingPathComponent("face.png"))
    try FileManager.default.createSymbolicLink(
      at: workDir.appendingPathComponent("link"), withDestinationURL: outsideDir)

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: [
        "image_path": "face.png",
        "output_path": "link/out.png",
        "_context": ["working_directory": workDir.path],
      ])

    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
    #expect(!FileManager.default.fileExists(atPath: outsideDir.appendingPathComponent("out.png").path))
  }

  @Test("Relative path inside the working directory still works", VisionRuntime.required)
  func testContainedPathAccepted() throws {
    try TestImageGenerator.setup()
    let base = TestImageGenerator.tempDir.appendingPathComponent("inside-\(UUID().uuidString)")
    let workDir = base.appendingPathComponent("work")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    let image = try TestImageGenerator.createColorImage()
    try FileManager.default.copyItem(at: image, to: workDir.appendingPathComponent("img.png"))

    let result = PluginInvoker.shared.invoke(
      tool: "detect_faces",
      args: [
        "image_path": "img.png",
        "_context": ["working_directory": workDir.path],
      ])

    #expect(result["faces"] as? [[String: Any]] != nil, "\(result)")
  }
}

@Suite("Parameter Bounds Tests", .serialized)
struct ParameterBoundsTests {

  private func expectInvalidArgs(_ result: [String: Any]) {
    #expect(result["ok"] as? Bool == false, "\(result)")
    #expect(result["kind"] as? String == "invalid_args", "\(result)")
    #expect(result["retryable"] as? Bool == false, "\(result)")
  }

  @Test("Negative max_results is rejected instead of trapping")
  func testNegativeMaxResults() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createColorImage()

    let result = PluginInvoker.shared.invoke(
      tool: "classify_image",
      args: ["image_path": image.path, "max_results": -1])
    expectInvalidArgs(result)
  }

  @Test("PDF dpi outside 1...600 is rejected")
  func testDPIBounds() throws {
    try TestImageGenerator.setup()
    let pdf = try TestImageGenerator.createTextPDF(text: "DPI bounds")

    for dpi in [0, -72, 10000] {
      let result = PluginInvoker.shared.invoke(
        tool: "detect_text",
        args: ["image_path": pdf.path, "dpi": dpi])
      expectInvalidArgs(result)
    }
  }

  @Test("Maximum allowed PDF dpi is accepted", VisionRuntime.required)
  func testDPIMaxAccepted() throws {
    try TestImageGenerator.setup()
    let pdf = try TestImageGenerator.createTextPDF(text: "DPI bounds")

    let ok = PluginInvoker.shared.invoke(
      tool: "detect_text",
      args: ["image_path": pdf.path, "dpi": 600])
    #expect(ok["text_blocks"] as? [[String: Any]] != nil, "\(ok)")
  }

  @Test("Zero or negative PDF page is rejected")
  func testPageBounds() throws {
    try TestImageGenerator.setup()
    let pdf = try TestImageGenerator.createTextPDF(text: "Page bounds")

    for page in [0, -3] {
      let result = PluginInvoker.shared.invoke(
        tool: "detect_text",
        args: ["image_path": pdf.path, "page": page])
      expectInvalidArgs(result)
    }
  }

  @Test("Unknown recognition_level is rejected")
  func testRecognitionLevelEnum() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createTextImage(text: "enum")

    let result = PluginInvoker.shared.invoke(
      tool: "detect_text",
      args: ["image_path": image.path, "recognition_level": "turbo"])
    expectInvalidArgs(result)
  }

  @Test("Out-of-range blur_radius is rejected")
  func testBlurRadiusBounds() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createFaceImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("blur-bounds.png")

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path, "blur_radius": -5])
    expectInvalidArgs(result)
  }

  @Test("Out-of-range padding and malformed aspect_ratio are rejected")
  func testAutoCropBounds() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createSceneImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("crop-bounds.png")

    let padding = PluginInvoker.shared.invoke(
      tool: "auto_crop",
      args: ["image_path": image.path, "output_path": output.path, "padding": 2.5])
    expectInvalidArgs(padding)

    let ratio = PluginInvoker.shared.invoke(
      tool: "auto_crop",
      args: ["image_path": image.path, "output_path": output.path, "aspect_ratio": "wide"])
    expectInvalidArgs(ratio)
  }

  @Test("Out-of-range max_hands is rejected")
  func testMaxHandsBounds() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createColorImage()

    let result = PluginInvoker.shared.invoke(
      tool: "detect_hand_pose",
      args: ["image_path": image.path, "max_hands": 0])
    expectInvalidArgs(result)
  }

  @Test("Out-of-range rectangle detection parameters are rejected")
  func testRectangleBounds() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createRectangleImage()

    let observations = PluginInvoker.shared.invoke(
      tool: "detect_rectangles",
      args: ["image_path": image.path, "max_observations": -1])
    expectInvalidArgs(observations)

    let confidence = PluginInvoker.shared.invoke(
      tool: "detect_rectangles",
      args: ["image_path": image.path, "min_confidence": 1.5])
    expectInvalidArgs(confidence)
  }

  @Test("Unknown saliency type is rejected")
  func testSaliencyTypeEnum() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createSceneImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("saliency-enum.png")

    let result = PluginInvoker.shared.invoke(
      tool: "generate_saliency_map",
      args: ["image_path": image.path, "output_path": output.path, "type": "heatmap"])
    expectInvalidArgs(result)
  }
}

// Every test here invokes blur_faces on a valid input image, which runs
// Vision face detection before any output handling — gate the whole suite.
@Suite("Output Encoding Tests", .serialized, VisionRuntime.required)
struct OutputEncodingTests {

  private func magicBytes(_ path: String, count: Int) throws -> [UInt8] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return Array(data.prefix(count))
  }

  @Test("PNG output path is encoded as PNG")
  func testPNGOutputEncodedAsPNG() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createFaceImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("enc-\(UUID().uuidString).png")

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path])

    #expect(result["output_path"] as? String == output.path, "\(result)")
    let magic = try magicBytes(output.path, count: 4)
    #expect(magic == [0x89, 0x50, 0x4E, 0x47], "expected PNG signature, got \(magic)")
  }

  @Test("JPEG output path is encoded as JPEG")
  func testJPEGOutputEncodedAsJPEG() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createFaceImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("enc-\(UUID().uuidString).jpg")

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path])

    #expect(result["output_path"] as? String == output.path, "\(result)")
    let magic = try magicBytes(output.path, count: 3)
    #expect(magic == [0xFF, 0xD8, 0xFF], "expected JPEG signature, got \(magic)")
  }

  @Test("Unsupported output extension is rejected")
  func testUnsupportedOutputExtension() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createFaceImage()
    let output = TestImageGenerator.tempDir.appendingPathComponent("enc-\(UUID().uuidString).webp")

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path])

    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }

  @Test("Overwriting an existing output leaves no temp files behind")
  func testOverwriteIsAtomic() throws {
    try TestImageGenerator.setup()
    let dir = TestImageGenerator.tempDir.appendingPathComponent("atomic-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = try TestImageGenerator.createFaceImage()
    let output = dir.appendingPathComponent("out.png")
    try Data([0x00]).write(to: output)

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path])

    #expect(result["output_path"] as? String == output.path, "\(result)")
    let magic = try magicBytes(output.path, count: 4)
    #expect(magic == [0x89, 0x50, 0x4E, 0x47])
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
      .filter { $0.contains(".tmp-") }
    #expect(leftovers.isEmpty)
  }

  @Test("Missing parent directory is created for output paths")
  func testParentDirectoryCreated() throws {
    try TestImageGenerator.setup()
    let image = try TestImageGenerator.createFaceImage()
    let output = TestImageGenerator.tempDir
      .appendingPathComponent("nested-\(UUID().uuidString)/deeper/out.png")

    let result = PluginInvoker.shared.invoke(
      tool: "blur_faces",
      args: ["image_path": image.path, "output_path": output.path])

    #expect(result["output_path"] as? String == output.path, "\(result)")
    #expect(FileManager.default.fileExists(atPath: output.path))
  }
}
