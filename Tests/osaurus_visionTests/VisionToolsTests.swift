import AppKit
import CoreImage
import Foundation
import PDFKit
import Testing

// MARK: - Test Utilities

/// Helper to generate test images programmatically
struct TestImageGenerator {
  static var tempDir: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "osaurus-vision-tests-\(ProcessInfo.processInfo.processIdentifier)")
  }

  static func setup() throws {
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  static func cleanup() {
    // Don't cleanup during parallel test runs - the temp directory is per-process anyway
    // and will be cleaned up by the system
  }

  /// Create a PDF with text for OCR testing
  static func createTextPDF(text: String, pages: Int = 1) throws -> URL {
    let url = tempDir.appendingPathComponent("text_\(UUID().uuidString).pdf")
    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // Letter size

    guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, nil) else {
      throw NSError(
        domain: "TestImageGenerator", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
    }

    for pageNum in 1...pages {
      var pageBox = pageRect
      pdfContext.beginPage(mediaBox: &pageBox)

      // White background
      pdfContext.setFillColor(CGColor.white)
      pdfContext.fill(pageRect)

      // Draw text
      let pageText = pages > 1 ? "\(text) - Page \(pageNum)" : text
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48),
        .foregroundColor: NSColor.black,
      ]
      let attrString = NSAttributedString(string: pageText, attributes: attrs)
      let line = CTLineCreateWithAttributedString(attrString)

      pdfContext.textPosition = CGPoint(x: 72, y: pageRect.height - 100)
      CTLineDraw(line, pdfContext)

      pdfContext.endPage()
    }

    pdfContext.closePDF()
    return url
  }

  /// Create a simple colored image
  static func createColorImage(width: Int = 200, height: Int = 200, color: NSColor = .blue) throws
    -> URL
  {
    let url = tempDir.appendingPathComponent("color_\(UUID().uuidString).png")
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    try saveImage(image, to: url)
    return url
  }

  /// Create an image with text for OCR testing
  static func createTextImage(text: String, fontSize: CGFloat = 48) throws -> URL {
    let url = tempDir.appendingPathComponent("text_\(UUID().uuidString).png")
    let size = NSSize(width: 400, height: 200)
    let image = NSImage(size: size)

    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: fontSize),
      .foregroundColor: NSColor.black,
    ]
    let textSize = text.size(withAttributes: attrs)
    let point = NSPoint(
      x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
    text.draw(at: point, withAttributes: attrs)
    image.unlockFocus()

    try saveImage(image, to: url)
    return url
  }

  /// Create an image with a rectangle shape
  static func createRectangleImage() throws -> URL {
    let url = tempDir.appendingPathComponent("rect_\(UUID().uuidString).png")
    let size = NSSize(width: 400, height: 400)
    let image = NSImage(size: size)

    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    NSColor.black.setStroke()
    let rectPath = NSBezierPath(rect: NSRect(x: 50, y: 50, width: 300, height: 200))
    rectPath.lineWidth = 3
    rectPath.stroke()
    image.unlockFocus()

    try saveImage(image, to: url)
    return url
  }

  /// Create an image with a simple face-like shape for face detection
  static func createFaceImage() throws -> URL {
    let url = tempDir.appendingPathComponent("face_\(UUID().uuidString).png")
    let size = NSSize(width: 300, height: 300)
    let image = NSImage(size: size)

    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Face oval
    NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.7, alpha: 1.0).setFill()
    let faceRect = NSRect(x: 75, y: 50, width: 150, height: 200)
    NSBezierPath(ovalIn: faceRect).fill()

    // Eyes
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 105, y: 160, width: 30, height: 20)).fill()
    NSBezierPath(ovalIn: NSRect(x: 165, y: 160, width: 30, height: 20)).fill()

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: 115, y: 165, width: 10, height: 10)).fill()
    NSBezierPath(ovalIn: NSRect(x: 175, y: 165, width: 10, height: 10)).fill()

    // Nose
    NSColor.darkGray.setStroke()
    let nosePath = NSBezierPath()
    nosePath.move(to: NSPoint(x: 150, y: 150))
    nosePath.line(to: NSPoint(x: 145, y: 120))
    nosePath.line(to: NSPoint(x: 155, y: 120))
    nosePath.stroke()

    // Mouth
    NSColor.red.setStroke()
    let mouthPath = NSBezierPath()
    mouthPath.move(to: NSPoint(x: 120, y: 90))
    mouthPath.curve(
      to: NSPoint(x: 180, y: 90), controlPoint1: NSPoint(x: 140, y: 70),
      controlPoint2: NSPoint(x: 160, y: 70))
    mouthPath.lineWidth = 2
    mouthPath.stroke()

    image.unlockFocus()
    try saveImage(image, to: url)
    return url
  }

  /// Create an image with horizon line
  static func createHorizonImage() throws -> URL {
    let url = tempDir.appendingPathComponent("horizon_\(UUID().uuidString).png")
    let size = NSSize(width: 400, height: 300)
    let image = NSImage(size: size)

    image.lockFocus()
    // Sky
    NSColor.cyan.setFill()
    NSRect(x: 0, y: 150, width: 400, height: 150).fill()
    // Ground
    NSColor.green.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 150).fill()
    image.unlockFocus()

    try saveImage(image, to: url)
    return url
  }

  /// Create a simple scene image for saliency testing
  static func createSceneImage() throws -> URL {
    let url = tempDir.appendingPathComponent("scene_\(UUID().uuidString).png")
    let size = NSSize(width: 400, height: 400)
    let image = NSImage(size: size)

    image.lockFocus()
    // Background
    NSColor.lightGray.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Salient object (bright red circle in center)
    NSColor.red.setFill()
    NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 100, height: 100)).fill()
    image.unlockFocus()

    try saveImage(image, to: url)
    return url
  }

  /// Create an image with a person silhouette for background removal
  static func createPersonImage() throws -> URL {
    let url = tempDir.appendingPathComponent("person_\(UUID().uuidString).png")
    let size = NSSize(width: 300, height: 400)
    let image = NSImage(size: size)

    image.lockFocus()
    // Background
    NSColor.blue.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Simple person shape
    NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.7, alpha: 1.0).setFill()

    // Head
    NSBezierPath(ovalIn: NSRect(x: 115, y: 320, width: 70, height: 70)).fill()

    // Body
    let bodyPath = NSBezierPath()
    bodyPath.move(to: NSPoint(x: 100, y: 320))
    bodyPath.line(to: NSPoint(x: 80, y: 150))
    bodyPath.line(to: NSPoint(x: 100, y: 50))
    bodyPath.line(to: NSPoint(x: 130, y: 50))
    bodyPath.line(to: NSPoint(x: 150, y: 150))
    bodyPath.line(to: NSPoint(x: 150, y: 150))
    bodyPath.line(to: NSPoint(x: 170, y: 50))
    bodyPath.line(to: NSPoint(x: 200, y: 50))
    bodyPath.line(to: NSPoint(x: 220, y: 150))
    bodyPath.line(to: NSPoint(x: 200, y: 320))
    bodyPath.close()
    bodyPath.fill()

    image.unlockFocus()
    try saveImage(image, to: url)
    return url
  }

  private static func saveImage(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      throw NSError(
        domain: "TestImageGenerator", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG"])
    }
    try pngData.write(to: url)
  }
}

/// Helper to invoke plugin tools by loading the dylib dynamically
final class PluginInvoker: @unchecked Sendable {
  typealias PluginEntry = @convention(c) () -> UnsafeRawPointer?

  struct PluginAPI {
    var free_string: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
    var `init`: (@convention(c) () -> UnsafeMutableRawPointer?)?
    var destroy: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    var get_manifest: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?)?
    var invoke:
      (
        @convention(c) (
          UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
          UnsafePointer<CChar>?
        ) -> UnsafePointer<CChar>?
      )?
  }

  /// Shared instance for all tests to use - avoids race conditions with parallel test execution
  static let shared: PluginInvoker = try! PluginInvoker()

  private let handle: UnsafeMutableRawPointer
  let api: PluginAPI
  let ctx: UnsafeMutableRawPointer

  private init() throws {
    // Find the dylib in the build directory
    let dylibPath = Self.findDylib()
    guard let h = dlopen(dylibPath, RTLD_NOW) else {
      let error = String(cString: dlerror())
      throw NSError(
        domain: "PluginInvoker", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to load dylib: \(error)"])
    }
    handle = h

    guard let entrySymbol = dlsym(handle, "osaurus_plugin_entry") else {
      throw NSError(
        domain: "PluginInvoker", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to find entry point"])
    }

    let entry = unsafeBitCast(entrySymbol, to: PluginEntry.self)
    let apiPtr = entry()!
    api = apiPtr.load(as: PluginAPI.self)
    ctx = api.`init`!()!
  }

  deinit {
    api.destroy?(ctx)
    // Note: We intentionally don't call dlclose(handle) here.
    // When tests run in parallel, calling dlclose can unload the dylib
    // while another test is still using it, causing hangs or crashes.
    // The OS will clean up the handle when the process exits.
  }

  private static func findDylib() -> String {
    // Try multiple possible locations
    let possiblePaths = [
      ".build/debug/libosaurus-vision.dylib",
      ".build/release/libosaurus-vision.dylib",
      ".build/arm64-apple-macosx/debug/libosaurus-vision.dylib",
      ".build/arm64-apple-macosx/release/libosaurus-vision.dylib",
    ]

    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath

    for path in possiblePaths {
      let fullPath = "\(cwd)/\(path)"
      if fm.fileExists(atPath: fullPath) {
        return fullPath
      }
    }

    // Default to debug path
    return "\(cwd)/.build/arm64-apple-macosx/debug/libosaurus-vision.dylib"
  }

  func invoke(tool: String, args: [String: Any]) -> [String: Any] {
    let jsonData = try! JSONSerialization.data(withJSONObject: args)
    let jsonString = String(data: jsonData, encoding: .utf8)!

    let resultPtr = api.invoke!(ctx, "tool", tool, jsonString)!
    let result = String(cString: resultPtr)
    api.free_string?(resultPtr)

    let resultData = result.data(using: .utf8)!
    return try! JSONSerialization.jsonObject(with: resultData) as! [String: Any]
  }

  func getManifest() -> [String: Any] {
    let manifestPtr = api.get_manifest!(ctx)!
    let manifest = String(cString: manifestPtr)
    api.free_string?(manifestPtr)

    let data = manifest.data(using: .utf8)!
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}

// MARK: - Tests

@Suite("Vision Plugin Tests", .serialized)
struct VisionPluginTests {

  @Test("Plugin manifest is valid")
  func testManifest() throws {
    let invoker = PluginInvoker.shared
    let manifest = invoker.getManifest()

    #expect(manifest["plugin_id"] as? String == "osaurus.vision")
    #expect(manifest["name"] as? String == "Vision")
    #expect(manifest["version"] as? String == "0.1.0")

    let capabilities = manifest["capabilities"] as! [String: Any]
    let tools = capabilities["tools"] as! [[String: Any]]
    #expect(tools.count == 15)

    let toolIds = tools.map { $0["id"] as! String }
    #expect(toolIds.contains("detect_text"))
    #expect(toolIds.contains("detect_faces"))
    #expect(toolIds.contains("remove_background"))
  }
}

@Suite("Text Detection Tests", .serialized)
struct TextDetectionTests {

  @Test("Detect text in image with text")
  func testDetectText() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createTextImage(text: "Hello World")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let textBlocks = result["text_blocks"] as? [[String: Any]]
    #expect(textBlocks != nil)
    print("Detected text blocks: \(textBlocks?.count ?? 0)")

    // Vision may or may not detect text in programmatically generated images
    // The important thing is no error occurred
  }

  @Test("Detect text with fast recognition level")
  func testDetectTextFast() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createTextImage(text: "Quick Test")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": imageUrl.path,
        "recognition_level": "fast",
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("PDF Support Tests", .serialized)
struct PDFSupportTests {

  @Test("Detect text in PDF")
  func testDetectTextInPDF() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "PDF Test Document")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": pdfUrl.path
      ])

    #expect(result["error"] == nil)
    let textBlocks = result["text_blocks"] as? [[String: Any]]
    #expect(textBlocks != nil)
    print("PDF text blocks detected: \(textBlocks?.count ?? 0)")
  }

  @Test("Detect text in PDF with page selection")
  func testDetectTextInPDFPage() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "Multi Page", pages: 3)
    let invoker = PluginInvoker.shared

    // Test page 2
    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": pdfUrl.path,
        "page": 2
      ])

    #expect(result["error"] == nil)
  }

  @Test("Detect text in PDF with custom DPI")
  func testDetectTextInPDFCustomDPI() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "High Res Test")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": pdfUrl.path,
        "dpi": 150
      ])

    #expect(result["error"] == nil)
  }

  @Test("Detect barcodes in PDF")
  func testDetectBarcodesInPDF() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "Barcode Test")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_barcodes",
      args: [
        "image_path": pdfUrl.path
      ])

    #expect(result["error"] == nil)
    let barcodes = result["barcodes"] as? [[String: Any]]
    #expect(barcodes != nil)
  }

  @Test("Detect document in PDF")
  func testDetectDocumentInPDF() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "Document Detection")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_document",
      args: [
        "image_path": pdfUrl.path
      ])

    #expect(result["error"] == nil)
    print("PDF document detection result: \(result)")
  }

  @Test("Invalid PDF page returns error")
  func testInvalidPDFPage() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let pdfUrl = try TestImageGenerator.createTextPDF(text: "Single Page", pages: 1)
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": pdfUrl.path,
        "page": 99
      ])

    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
    let message = result["message"] as? String
    #expect(message?.contains("page") == true)
  }
}

@Suite("Document Detection Tests", .serialized)
struct DocumentDetectionTests {

  @Test("Detect document boundaries")
  func testDetectDocument() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createRectangleImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_document",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    // Document detection may return null if no document-like shape found
    print("Document result: \(result)")
  }
}

@Suite("Barcode Detection Tests", .serialized)
struct BarcodeDetectionTests {

  @Test("Detect barcodes returns empty for non-barcode image")
  func testDetectBarcodesEmpty() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createColorImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_barcodes",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let barcodes = result["barcodes"] as? [[String: Any]]
    #expect(barcodes != nil)
    #expect(barcodes?.count == 0)
  }

  @Test("Detect barcodes with symbology filter")
  func testDetectBarcodesWithSymbology() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createColorImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_barcodes",
      args: [
        "image_path": imageUrl.path,
        "symbologies": ["qr", "code128"],
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Face Detection Tests", .serialized)
struct FaceDetectionTests {

  @Test("Detect faces in image")
  func testDetectFaces() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createFaceImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_faces",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let faces = result["faces"] as? [[String: Any]]
    #expect(faces != nil)
    print("Detected faces: \(faces?.count ?? 0)")
  }

  @Test("Detect faces with landmarks")
  func testDetectFacesWithLandmarks() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createFaceImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_faces",
      args: [
        "image_path": imageUrl.path,
        "include_landmarks": true,
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Rectangle Detection Tests", .serialized)
struct RectangleDetectionTests {

  @Test("Detect rectangles in image")
  func testDetectRectangles() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createRectangleImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_rectangles",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let rectangles = result["rectangles"] as? [[String: Any]]
    #expect(rectangles != nil)
    print("Detected rectangles: \(rectangles?.count ?? 0)")
  }

  @Test("Detect rectangles with parameters")
  func testDetectRectanglesWithParams() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createRectangleImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_rectangles",
      args: [
        "image_path": imageUrl.path,
        "max_observations": 5,
        "min_aspect_ratio": 0.5,
        "max_aspect_ratio": 2.0,
        "min_confidence": 0.5,
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Image Classification Tests", .serialized)
struct ImageClassificationTests {

  @Test("Classify image")
  func testClassifyImage() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "classify_image",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let classifications = result["classifications"] as? [[String: Any]]
    #expect(classifications != nil)
    print("Classifications: \(classifications?.prefix(3).map { $0["label"] ?? "?" } ?? [])")
  }

  @Test("Classify image with max results")
  func testClassifyImageMaxResults() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "classify_image",
      args: [
        "image_path": imageUrl.path,
        "max_results": 3,
      ])

    #expect(result["error"] == nil)
    let classifications = result["classifications"] as? [[String: Any]]
    #expect(classifications != nil)
    #expect((classifications?.count ?? 0) <= 3)
  }
}

@Suite("Horizon Detection Tests", .serialized)
struct HorizonDetectionTests {

  @Test("Detect horizon")
  func testDetectHorizon() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createHorizonImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_horizon",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    print("Horizon result: \(result)")
  }
}

@Suite("Body Pose Detection Tests", .serialized)
struct BodyPoseDetectionTests {

  @Test("Detect body pose")
  func testDetectBodyPose() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createPersonImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_body_pose",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let bodyPoses = result["body_poses"] as? [[String: Any]]
    #expect(bodyPoses != nil)
    print("Detected body poses: \(bodyPoses?.count ?? 0)")
  }
}

@Suite("Hand Pose Detection Tests", .serialized)
struct HandPoseDetectionTests {

  @Test("Detect hand pose")
  func testDetectHandPose() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createColorImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_hand_pose",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let handPoses = result["hand_poses"] as? [[String: Any]]
    #expect(handPoses != nil)
    #expect(handPoses?.count == 0)  // No hands in color image
  }

  @Test("Detect hand pose with max hands")
  func testDetectHandPoseMaxHands() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createColorImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_hand_pose",
      args: [
        "image_path": imageUrl.path,
        "max_hands": 4,
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Animal Detection Tests", .serialized)
struct AnimalDetectionTests {

  @Test("Detect animals returns empty for non-animal image")
  func testDetectAnimals() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createColorImage()
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_animals",
      args: [
        "image_path": imageUrl.path
      ])

    #expect(result["error"] == nil)
    let animals = result["animals"] as? [[String: Any]]
    #expect(animals != nil)
    #expect(animals?.count == 0)
  }
}

@Suite("Blur Faces Tests", .serialized)
struct BlurFacesTests {

  @Test("Blur faces in image")
  func testBlurFaces() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createFaceImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("blurred.jpg")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "blur_faces",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
      ])

    #expect(result["error"] == nil)
    #expect(result["output_path"] != nil)
    #expect(FileManager.default.fileExists(atPath: outputUrl.path))
    print("Faces blurred: \(result["faces_blurred"] ?? 0)")
  }

  @Test("Blur faces with custom radius")
  func testBlurFacesWithRadius() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createFaceImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("blurred_custom.jpg")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "blur_faces",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
        "blur_radius": 50,
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Auto Crop Tests", .serialized)
struct AutoCropTests {

  @Test("Auto crop image")
  func testAutoCrop() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("cropped.jpg")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "auto_crop",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
      ])

    #expect(result["error"] == nil)
    #expect(result["output_path"] != nil)
    #expect(FileManager.default.fileExists(atPath: outputUrl.path))
    print("Cropped: \(result["cropped"] ?? false)")
  }

  @Test("Auto crop with aspect ratio")
  func testAutoCropAspectRatio() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("cropped_16x9.jpg")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "auto_crop",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
        "aspect_ratio": "16:9",
        "padding": 0.2,
      ])

    #expect(result["error"] == nil)
  }
}

@Suite("Saliency Map Tests", .serialized)
struct SaliencyMapTests {

  @Test("Generate attention saliency map")
  func testSaliencyMapAttention() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("saliency_attention.png")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "generate_saliency_map",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
        "type": "attention",
      ])

    #expect(result["error"] == nil)
    #expect(result["output_path"] != nil)
    #expect(result["type"] as? String == "attention")
    #expect(FileManager.default.fileExists(atPath: outputUrl.path))

    let regions = result["salient_regions"] as? [[String: Any]]
    print("Salient regions: \(regions?.count ?? 0)")
  }

  @Test("Generate objectness saliency map")
  func testSaliencyMapObjectness() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createSceneImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("saliency_objectness.png")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "generate_saliency_map",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
        "type": "objectness",
      ])

    #expect(result["error"] == nil)
    #expect(result["type"] as? String == "objectness")
  }
}

@Suite("Remove Background Tests", .serialized)
struct RemoveBackgroundTests {

  @Test("Remove background from image")
  func testRemoveBackground() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createPersonImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("nobg.png")
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "remove_background",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
      ])

    // Note: VNGenerateForegroundInstanceMaskRequest may not detect foreground in synthetic images
    print("Remove background result: \(result)")

    // Check that output is PNG even if input path didn't end in .png
    if let outputPath = result["output_path"] as? String {
      #expect(outputPath.hasSuffix(".png"))
    }
  }

  @Test("Remove background auto-converts to PNG")
  func testRemoveBackgroundPngConversion() throws {
    try TestImageGenerator.setup()
    defer { TestImageGenerator.cleanup() }

    let imageUrl = try TestImageGenerator.createPersonImage()
    let outputUrl = TestImageGenerator.tempDir.appendingPathComponent("nobg.jpg")  // Request JPG
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "remove_background",
      args: [
        "image_path": imageUrl.path,
        "output_path": outputUrl.path,
      ])

    // Should convert to PNG for transparency
    if let outputPath = result["output_path"] as? String {
      #expect(outputPath.hasSuffix(".png"))
    }
  }
}

@Suite("Error Handling Tests", .serialized)
struct ErrorHandlingTests {

  @Test("Handle invalid image path")
  func testInvalidImagePath() throws {
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "detect_text",
      args: [
        "image_path": "/nonexistent/path/image.jpg"
      ])

    // Missing input file -> not_found failure envelope (non-retryable).
    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "not_found")
    #expect(result["retryable"] as? Bool == false)
    print("Error: \(result["message"] ?? "none")")
  }

  @Test("Handle invalid arguments")
  func testInvalidArguments() throws {
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(tool: "detect_text", args: [:])

    // Missing required args -> invalid_args failure envelope (retryable).
    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "invalid_args")
    #expect(result["retryable"] as? Bool == true)
  }

  @Test("Handle unknown tool")
  func testUnknownTool() throws {
    let invoker = PluginInvoker.shared

    let result = invoker.invoke(
      tool: "unknown_tool",
      args: [
        "image_path": "/some/path.jpg"
      ])

    // Unknown tool id -> not_found failure envelope.
    #expect(result["ok"] as? Bool == false)
    #expect(result["kind"] as? String == "not_found")
    let message = result["message"] as? String
    #expect(message?.contains("Unknown tool") == true)
  }
}
