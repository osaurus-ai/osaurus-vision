import AppKit
import CoreImage
import Foundation
import PDFKit
import Vision

// MARK: - Injected Context

private struct FolderContext: Decodable {
  let working_directory: String
}

// MARK: - Vision Helper

private enum VisionError: Error, LocalizedError {
  case imageLoadFailed(String)
  case invalidPath(String)
  case saveFailed(String)
  case fileNotFound(String)
  case invalidArguments(String)

  var errorDescription: String? { message }

  /// Human-readable message embedded in the failure envelope.
  var message: String {
    switch self {
    case .imageLoadFailed(let path): return "Failed to load image: \(path)"
    case .invalidPath(let path): return "Invalid path: \(path)"
    case .saveFailed(let path): return "Failed to save image: \(path)"
    case .fileNotFound(let path): return "File not found: \(path)"
    case .invalidArguments(let detail): return detail
    }
  }

  /// Maps each failure to the canonical host envelope kind.
  /// - invalid path / bad arguments -> invalid_args
  /// - missing input file           -> not_found
  /// - load / Vision / save failure -> execution_error
  var kind: Envelope.Kind {
    switch self {
    case .invalidPath, .invalidArguments: return .invalidArgs
    case .fileNotFound: return .notFound
    case .imageLoadFailed, .saveFailed: return .executionError
    }
  }
}

private enum VisionHelper {
  static func resolvePath(_ path: String, context: FolderContext?) -> String {
    guard !path.hasPrefix("/"), let workingDir = context?.working_directory else { return path }
    return "\(workingDir)/\(path)"
  }

  static func validatePath(_ absolutePath: String, context: FolderContext?) -> Bool {
    guard let workingDir = context?.working_directory else { return true }
    return URL(fileURLWithPath: absolutePath).standardized.path.hasPrefix(workingDir)
  }

  static func loadImage(from path: String, context: FolderContext?) throws -> CGImage {
    guard !path.isEmpty else {
      throw VisionError.invalidArguments("image_path must not be empty")
    }
    let absolutePath = resolvePath(path, context: context)
    guard validatePath(absolutePath, context: context) else {
      throw VisionError.invalidPath("Path outside working directory")
    }
    guard FileManager.default.fileExists(atPath: absolutePath) else {
      throw VisionError.fileNotFound(absolutePath)
    }
    guard let nsImage = NSImage(contentsOfFile: absolutePath),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      throw VisionError.imageLoadFailed(absolutePath)
    }
    return cgImage
  }

  /// Load image from file, with PDF support (renders specific page at given DPI)
  static func loadImageOrPDF(
    from path: String, context: FolderContext?, page: Int = 1, dpi: Int = 300
  ) throws -> CGImage {
    guard !path.isEmpty else {
      throw VisionError.invalidArguments("image_path must not be empty")
    }
    let absolutePath = resolvePath(path, context: context)
    guard validatePath(absolutePath, context: context) else {
      throw VisionError.invalidPath("Path outside working directory")
    }
    guard FileManager.default.fileExists(atPath: absolutePath) else {
      throw VisionError.fileNotFound(absolutePath)
    }

    let url = URL(fileURLWithPath: absolutePath)

    // Check if it's a PDF
    if url.pathExtension.lowercased() == "pdf" {
      return try loadPDFPage(from: url, page: page, dpi: dpi)
    }

    // Otherwise load as regular image
    guard let nsImage = NSImage(contentsOfFile: absolutePath),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      throw VisionError.imageLoadFailed(absolutePath)
    }
    return cgImage
  }

  /// Load a specific page from a PDF at given DPI
  static func loadPDFPage(from url: URL, page: Int, dpi: Int) throws -> CGImage {
    guard let pdfDocument = PDFDocument(url: url) else {
      throw VisionError.imageLoadFailed("Failed to load PDF: \(url.path)")
    }

    let pageIndex = page - 1  // Convert to 0-based index
    guard pageIndex >= 0, pageIndex < pdfDocument.pageCount,
      let pdfPage = pdfDocument.page(at: pageIndex)
    else {
      throw VisionError.invalidArguments(
        "PDF page \(page) not found (document has \(pdfDocument.pageCount) pages)")
    }

    // Get page bounds and calculate render size
    let pageRect = pdfPage.bounds(for: .mediaBox)
    let scale = CGFloat(dpi) / 72.0  // PDF points are 72 per inch
    let width = Int(pageRect.width * scale)
    let height = Int(pageRect.height * scale)

    // Create bitmap context
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw VisionError.imageLoadFailed("Failed to create graphics context")
    }

    // Fill with white background
    context.setFillColor(CGColor.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Scale and render PDF page
    context.scaleBy(x: scale, y: scale)
    pdfPage.draw(with: .mediaBox, to: context)

    guard let cgImage = context.makeImage() else {
      throw VisionError.imageLoadFailed("Failed to render PDF page")
    }

    return cgImage
  }

  /// Get PDF page count
  static func getPDFPageCount(from path: String, context: FolderContext?) -> Int? {
    let absolutePath = resolvePath(path, context: context)
    let url = URL(fileURLWithPath: absolutePath)
    guard url.pathExtension.lowercased() == "pdf",
      let pdfDocument = PDFDocument(url: url)
    else {
      return nil
    }
    return pdfDocument.pageCount
  }

  static func saveCIImage(_ image: CIImage, to path: String, context: FolderContext?) throws {
    let absolutePath = resolvePath(path, context: context)
    guard validatePath(absolutePath, context: context) else {
      throw VisionError.invalidPath("Path outside working directory")
    }

    let url = URL(fileURLWithPath: absolutePath)
    let ciContext = CIContext()

    // Create parent directory if needed
    let parentDir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    // Normalize the image extent to start at origin
    var imageToSave = image
    if !imageToSave.extent.origin.equalTo(.zero) {
      imageToSave = imageToSave.transformed(
        by: CGAffineTransform(
          translationX: -imageToSave.extent.origin.x,
          y: -imageToSave.extent.origin.y
        ))
    }

    // Handle infinite extent
    if imageToSave.extent.isInfinite {
      imageToSave = imageToSave.cropped(to: CGRect(x: 0, y: 0, width: 4096, height: 4096))
    }

    // Render to CGImage first (more reliable)
    guard let cgImage = ciContext.createCGImage(imageToSave, from: imageToSave.extent) else {
      throw VisionError.saveFailed("Failed to render image")
    }

    let nsImage = NSImage(
      cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

    guard let tiffData = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData)
    else {
      throw VisionError.saveFailed("Failed to create bitmap")
    }

    let isPNG = url.pathExtension.lowercased() == "png"
    let data: Data?
    if isPNG {
      data = bitmap.representation(using: .png, properties: [:])
    } else {
      data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    guard let imageData = data else {
      throw VisionError.saveFailed("Failed to encode image")
    }

    try imageData.write(to: url)
  }

  static func denormalizeRect(_ rect: CGRect, imageSize: CGSize) -> [String: Double] {
    [
      "x": rect.origin.x * imageSize.width,
      "y": (1 - rect.origin.y - rect.height) * imageSize.height,
      "width": rect.width * imageSize.width,
      "height": rect.height * imageSize.height,
    ]
  }

  static func denormalizePoint(_ point: CGPoint, imageSize: CGSize) -> [String: Double] {
    ["x": point.x * imageSize.width, "y": (1 - point.y) * imageSize.height]
  }

  /// Serializes a successful result payload. The host auto-wraps this
  /// non-envelope success output as {"ok":true,"result":<payload>}, so the
  /// success shape is intentionally left unwrapped here. Only the encoding
  /// failure path emits an explicit failure envelope.
  static func jsonResult(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
      let json = String(data: data, encoding: .utf8)
    else {
      return Envelope.failure(.executionError, "JSON encoding failed")
    }
    return json
  }
}

// MARK: - Tool Protocol

private protocol VisionTool {
  associatedtype Args: Decodable
  var name: String { get }
  func execute(input: Args) throws -> [String: Any]
}

extension VisionTool {
  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return Envelope.failure(.invalidArgs, "Invalid arguments")
    }
    do {
      return VisionHelper.jsonResult(try execute(input: input))
    } catch let error as VisionError {
      return Envelope.failure(error.kind, error.message)
    } catch {
      return Envelope.failure(.executionError, error.localizedDescription)
    }
  }
}

// MARK: - Detection Tools

private struct DetectTextTool: VisionTool {
  let name = "detect_text"

  struct Args: Decodable {
    let image_path: String
    let recognition_level: String?
    let languages: [String]?
    let page: Int?  // PDF page number (1-indexed)
    let dpi: Int?  // PDF render resolution (default: 300)
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImageOrPDF(
      from: input.image_path,
      context: input._context,
      page: input.page ?? 1,
      dpi: input.dpi ?? 300
    )
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = input.recognition_level == "fast" ? .fast : .accurate
    if let languages = input.languages { request.recognitionLanguages = languages }

    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs -> [String: Any] in
      let candidate = obs.topCandidates(1).first
      return [
        "text": candidate?.string ?? "",
        "confidence": candidate?.confidence ?? 0,
        "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
      ]
    }
    return ["text_blocks": results]
  }
}

private struct DetectDocumentTool: VisionTool {
  let name = "detect_document"

  struct Args: Decodable {
    let image_path: String
    let page: Int?  // PDF page number (1-indexed)
    let dpi: Int?  // PDF render resolution (default: 300)
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImageOrPDF(
      from: input.image_path,
      context: input._context,
      page: input.page ?? 1,
      dpi: input.dpi ?? 300
    )
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectDocumentSegmentationRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    guard let obs = request.results?.first else { return ["document": NSNull()] }

    return [
      "document": [
        "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
        "corners": [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
          .map { VisionHelper.denormalizePoint($0, imageSize: imageSize) },
        "confidence": obs.confidence,
      ]
    ]
  }
}

private struct DetectBarcodesTool: VisionTool {
  let name = "detect_barcodes"

  struct Args: Decodable {
    let image_path: String
    let symbologies: [String]?
    let page: Int?  // PDF page number (1-indexed)
    let dpi: Int?  // PDF render resolution (default: 300)
    let _context: FolderContext?
  }

  private static let symbologyMap: [String: VNBarcodeSymbology] = [
    "qr": .qr, "aztec": .aztec, "code128": .code128, "code39": .code39,
    "code93": .code93, "datamatrix": .dataMatrix, "ean8": .ean8,
    "ean13": .ean13, "itf14": .itf14, "pdf417": .pdf417, "upce": .upce,
  ]

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImageOrPDF(
      from: input.image_path,
      context: input._context,
      page: input.page ?? 1,
      dpi: input.dpi ?? 300
    )
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectBarcodesRequest()
    if let syms = input.symbologies {
      let mapped = syms.compactMap { Self.symbologyMap[$0.lowercased()] }
      if !mapped.isEmpty { request.symbologies = mapped }
    }

    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs in
      [
        "symbology": obs.symbology.rawValue,
        "payload": obs.payloadStringValue ?? "",
        "confidence": obs.confidence,
        "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
      ] as [String: Any]
    }
    return ["barcodes": results]
  }
}

private struct DetectFacesTool: VisionTool {
  let name = "detect_faces"

  struct Args: Decodable {
    let image_path: String
    let include_landmarks: Bool?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    if input.include_landmarks == true {
      let request = VNDetectFaceLandmarksRequest()
      try handler.perform([request])

      let results = (request.results ?? []).map { obs -> [String: Any] in
        var data: [String: Any] = [
          "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
          "confidence": obs.confidence,
          "roll": obs.roll?.doubleValue as Any,
          "yaw": obs.yaw?.doubleValue as Any,
          "pitch": obs.pitch?.doubleValue as Any,
        ]

        if let lm = obs.landmarks {
          data["landmarks"] = [
            "left_eye": lm.leftEye.map {
              extractPoints($0, imageSize: imageSize, boundingBox: obs.boundingBox)
            },
            "right_eye": lm.rightEye.map {
              extractPoints($0, imageSize: imageSize, boundingBox: obs.boundingBox)
            },
            "nose": lm.nose.map {
              extractPoints($0, imageSize: imageSize, boundingBox: obs.boundingBox)
            },
            "outer_lips": lm.outerLips.map {
              extractPoints($0, imageSize: imageSize, boundingBox: obs.boundingBox)
            },
            "face_contour": lm.faceContour.map {
              extractPoints($0, imageSize: imageSize, boundingBox: obs.boundingBox)
            },
          ].compactMapValues { $0 }
        }
        return data
      }
      return ["faces": results]
    } else {
      let request = VNDetectFaceRectanglesRequest()
      try handler.perform([request])

      let results = (request.results ?? []).map { obs in
        [
          "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
          "confidence": obs.confidence,
          "roll": obs.roll?.doubleValue as Any,
          "yaw": obs.yaw?.doubleValue as Any,
          "pitch": obs.pitch?.doubleValue as Any,
        ] as [String: Any]
      }
      return ["faces": results]
    }
  }

  private func extractPoints(
    _ region: VNFaceLandmarkRegion2D, imageSize: CGSize, boundingBox: CGRect
  ) -> [[String: Double]] {
    (0..<region.pointCount).map { i in
      let pt = region.normalizedPoints[i]
      let imgPt = CGPoint(
        x: boundingBox.origin.x + pt.x * boundingBox.width,
        y: boundingBox.origin.y + pt.y * boundingBox.height
      )
      return VisionHelper.denormalizePoint(imgPt, imageSize: imageSize)
    }
  }
}

private struct DetectRectanglesTool: VisionTool {
  let name = "detect_rectangles"

  struct Args: Decodable {
    let image_path: String
    let max_observations: Int?
    let min_aspect_ratio: Double?
    let max_aspect_ratio: Double?
    let min_confidence: Double?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectRectanglesRequest()
    request.maximumObservations = input.max_observations ?? 10
    request.minimumAspectRatio = Float(input.min_aspect_ratio ?? 0.0)
    request.maximumAspectRatio = Float(input.max_aspect_ratio ?? 1.0)
    request.minimumConfidence = Float(input.min_confidence ?? 0.0)

    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs in
      [
        "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
        "confidence": obs.confidence,
        "corners": [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
          .map { VisionHelper.denormalizePoint($0, imageSize: imageSize) },
      ] as [String: Any]
    }
    return ["rectangles": results]
  }
}

private struct ClassifyImageTool: VisionTool {
  let name = "classify_image"

  struct Args: Decodable {
    let image_path: String
    let max_results: Int?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)

    let request = VNClassifyImageRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).prefix(input.max_results ?? 10).map {
      ["label": $0.identifier, "confidence": $0.confidence] as [String: Any]
    }
    return ["classifications": Array(results)]
  }
}

private struct DetectHorizonTool: VisionTool {
  let name = "detect_horizon"

  struct Args: Decodable {
    let image_path: String
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)

    let request = VNDetectHorizonRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    guard let obs = request.results?.first else { return ["horizon": NSNull()] }

    return [
      "horizon": [
        "angle_degrees": obs.angle * 180.0 / .pi,
        "angle_radians": obs.angle,
        "confidence": obs.confidence,
      ]
    ]
  }
}

private struct DetectBodyPoseTool: VisionTool {
  let name = "detect_body_pose"

  struct Args: Decodable {
    let image_path: String
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectHumanBodyPoseRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs -> [String: Any] in
      var joints: [String: Any] = [:]
      if let points = try? obs.recognizedPoints(.all) {
        for (key, pt) in points where pt.confidence > 0.1 {
          joints[key.rawValue.rawValue] = [
            "x": pt.location.x * imageSize.width,
            "y": (1 - pt.location.y) * imageSize.height,
            "confidence": pt.confidence,
          ]
        }
      }
      return ["confidence": obs.confidence, "joints": joints]
    }
    return ["body_poses": results]
  }
}

private struct DetectHandPoseTool: VisionTool {
  let name = "detect_hand_pose"

  struct Args: Decodable {
    let image_path: String
    let max_hands: Int?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = input.max_hands ?? 2
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs -> [String: Any] in
      var joints: [String: Any] = [:]
      if let points = try? obs.recognizedPoints(.all) {
        for (key, pt) in points where pt.confidence > 0.1 {
          joints[key.rawValue.rawValue] = [
            "x": pt.location.x * imageSize.width,
            "y": (1 - pt.location.y) * imageSize.height,
            "confidence": pt.confidence,
          ]
        }
      }
      let chirality: String =
        switch obs.chirality {
        case .left: "left"
        case .right: "right"
        default: "unknown"
        }
      return ["confidence": obs.confidence, "chirality": chirality, "joints": joints]
    }
    return ["hand_poses": results]
  }
}

private struct DetectAnimalsTool: VisionTool {
  let name = "detect_animals"

  struct Args: Decodable {
    let image_path: String
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNRecognizeAnimalsRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let results = (request.results ?? []).map { obs in
      [
        "bounding_box": VisionHelper.denormalizeRect(obs.boundingBox, imageSize: imageSize),
        "confidence": obs.confidence,
        "labels": obs.labels.map { ["identifier": $0.identifier, "confidence": $0.confidence] },
      ] as [String: Any]
    }
    return ["animals": results]
  }
}

// MARK: - Image Processing Tools

private struct BlurFacesTool: VisionTool {
  let name = "blur_faces"

  struct Args: Decodable {
    let image_path: String
    let output_path: String
    let blur_radius: Double?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    var ciImage = CIImage(cgImage: cgImage)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNDetectFaceRectanglesRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let faces = request.results ?? []
    guard !faces.isEmpty else {
      try VisionHelper.saveCIImage(ciImage, to: input.output_path, context: input._context)
      return [
        "output_path": VisionHelper.resolvePath(input.output_path, context: input._context),
        "faces_blurred": 0,
      ]
    }

    guard let blurFilter = CIFilter(name: "CIGaussianBlur"),
      let blendFilter = CIFilter(name: "CIBlendWithMask")
    else {
      throw VisionError.saveFailed("Failed to create filters")
    }

    blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
    blurFilter.setValue(input.blur_radius ?? 30.0, forKey: kCIInputRadiusKey)
    guard let blurredImage = blurFilter.outputImage else {
      throw VisionError.saveFailed("Failed to apply blur")
    }

    for face in faces {
      let faceRect = CGRect(
        x: face.boundingBox.origin.x * imageSize.width,
        y: face.boundingBox.origin.y * imageSize.height,
        width: face.boundingBox.width * imageSize.width,
        height: face.boundingBox.height * imageSize.height
      ).insetBy(
        dx: -face.boundingBox.width * imageSize.width * 0.1,
        dy: -face.boundingBox.height * imageSize.height * 0.1)

      let maskImage = CIImage(color: CIColor.white).cropped(to: faceRect)
      blendFilter.setValue(blurredImage, forKey: kCIInputImageKey)
      blendFilter.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
      blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

      if let result = blendFilter.outputImage {
        ciImage = result.cropped(to: CGRect(origin: .zero, size: imageSize))
      }
    }

    try VisionHelper.saveCIImage(ciImage, to: input.output_path, context: input._context)
    return [
      "output_path": VisionHelper.resolvePath(input.output_path, context: input._context),
      "faces_blurred": faces.count,
    ]
  }
}

private struct AutoCropTool: VisionTool {
  let name = "auto_crop"

  struct Args: Decodable {
    let image_path: String
    let output_path: String
    let aspect_ratio: String?
    let padding: Double?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let ciImage = CIImage(cgImage: cgImage)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

    let request = VNGenerateAttentionBasedSaliencyImageRequest()
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    guard let obs = request.results?.first, let salientObjects = obs.salientObjects,
      !salientObjects.isEmpty
    else {
      try VisionHelper.saveCIImage(ciImage, to: input.output_path, context: input._context)
      return [
        "output_path": VisionHelper.resolvePath(input.output_path, context: input._context),
        "cropped": false,
      ]
    }

    let unionRect = salientObjects.reduce(salientObjects[0].boundingBox) {
      $0.union($1.boundingBox)
    }
    var cropRect = CGRect(
      x: unionRect.origin.x * imageSize.width,
      y: unionRect.origin.y * imageSize.height,
      width: unionRect.width * imageSize.width,
      height: unionRect.height * imageSize.height
    )

    let padding = input.padding ?? 0.1
    cropRect = cropRect.insetBy(dx: -cropRect.width * padding, dy: -cropRect.height * padding)
    cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

    if let ratio = input.aspect_ratio, let (w, h) = parseAspectRatio(ratio) {
      let targetRatio = w / h
      let currentRatio = cropRect.width / cropRect.height
      if currentRatio > targetRatio {
        let newWidth = cropRect.height * targetRatio
        cropRect.origin.x += (cropRect.width - newWidth) / 2
        cropRect.size.width = newWidth
      } else {
        let newHeight = cropRect.width / targetRatio
        cropRect.origin.y += (cropRect.height - newHeight) / 2
        cropRect.size.height = newHeight
      }
    }

    let croppedImage = ciImage.cropped(to: cropRect)
      .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

    try VisionHelper.saveCIImage(croppedImage, to: input.output_path, context: input._context)
    return [
      "output_path": VisionHelper.resolvePath(input.output_path, context: input._context),
      "cropped": true,
      "crop_rect": [
        "x": cropRect.origin.x,
        "y": imageSize.height - cropRect.origin.y - cropRect.height,
        "width": cropRect.width,
        "height": cropRect.height,
      ],
    ]
  }

  private func parseAspectRatio(_ str: String) -> (Double, Double)? {
    let parts = str.split(separator: ":")
    guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
    return (w, h)
  }
}

private struct GenerateSaliencyMapTool: VisionTool {
  let name = "generate_saliency_map"

  struct Args: Decodable {
    let image_path: String
    let output_path: String
    let type: String?
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
    let saliencyType = input.type ?? "attention"

    let request: VNImageBasedRequest =
      saliencyType == "objectness"
      ? VNGenerateObjectnessBasedSaliencyImageRequest()
      : VNGenerateAttentionBasedSaliencyImageRequest()

    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

    let observation: VNSaliencyImageObservation? =
      saliencyType == "objectness"
      ? (request as? VNGenerateObjectnessBasedSaliencyImageRequest)?.results?.first
      : (request as? VNGenerateAttentionBasedSaliencyImageRequest)?.results?.first

    guard let obs = observation else {
      throw VisionError.saveFailed("Failed to generate saliency map")
    }

    var saliencyImage = CIImage(cvPixelBuffer: obs.pixelBuffer)
    let scaleX = imageSize.width / saliencyImage.extent.width
    let scaleY = imageSize.height / saliencyImage.extent.height
    saliencyImage = saliencyImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    if let colorFilter = CIFilter(name: "CIFalseColor") {
      colorFilter.setValue(saliencyImage, forKey: kCIInputImageKey)
      colorFilter.setValue(CIColor.blue, forKey: "inputColor0")
      colorFilter.setValue(CIColor.red, forKey: "inputColor1")
      if let colored = colorFilter.outputImage { saliencyImage = colored }
    }

    try VisionHelper.saveCIImage(saliencyImage, to: input.output_path, context: input._context)

    let regions = (obs.salientObjects ?? []).map { obj in
      [
        "bounding_box": VisionHelper.denormalizeRect(obj.boundingBox, imageSize: imageSize),
        "confidence": obj.confidence,
      ] as [String: Any]
    }

    return [
      "output_path": VisionHelper.resolvePath(input.output_path, context: input._context),
      "type": saliencyType,
      "salient_regions": regions,
    ]
  }
}

private struct RemoveBackgroundTool: VisionTool {
  let name = "remove_background"

  struct Args: Decodable {
    let image_path: String
    let output_path: String
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    let cgImage = try VisionHelper.loadImage(from: input.image_path, context: input._context)
    let ciImage = CIImage(cgImage: cgImage)

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    guard let obs = request.results?.first else {
      throw VisionError.saveFailed("No foreground detected")
    }

    let maskPixelBuffer = try obs.generateScaledMaskForImage(
      forInstances: obs.allInstances, from: handler)
    let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

    guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
      throw VisionError.saveFailed("Failed to create blend filter")
    }

    let transparentBg = CIImage(color: CIColor.clear).cropped(to: ciImage.extent)
    blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
    blendFilter.setValue(transparentBg, forKey: kCIInputBackgroundImageKey)
    blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

    guard let outputImage = blendFilter.outputImage else {
      throw VisionError.saveFailed("Failed to apply mask")
    }

    var outputPath = input.output_path
    if !outputPath.lowercased().hasSuffix(".png") {
      outputPath = outputPath.replacingOccurrences(
        of: "\\.[^.]+$", with: ".png", options: .regularExpression)
      if !outputPath.hasSuffix(".png") { outputPath += ".png" }
    }

    try VisionHelper.saveCIImage(outputImage, to: outputPath, context: input._context)
    return [
      "output_path": VisionHelper.resolvePath(outputPath, context: input._context),
      "instances_detected": obs.allInstances.count,
    ]
  }
}

// MARK: - PDF Info Tool

private struct GetPDFInfoTool: VisionTool {
  let name = "get_pdf_info"

  struct Args: Decodable {
    let pdf_path: String
    let _context: FolderContext?
  }

  func execute(input: Args) throws -> [String: Any] {
    guard !input.pdf_path.isEmpty else {
      throw VisionError.invalidArguments("pdf_path must not be empty")
    }
    let absolutePath = VisionHelper.resolvePath(input.pdf_path, context: input._context)
    guard VisionHelper.validatePath(absolutePath, context: input._context) else {
      throw VisionError.invalidPath("Path outside working directory")
    }

    let url = URL(fileURLWithPath: absolutePath)
    guard url.pathExtension.lowercased() == "pdf" else {
      throw VisionError.invalidArguments("File is not a PDF: \(input.pdf_path)")
    }

    guard FileManager.default.fileExists(atPath: absolutePath) else {
      throw VisionError.fileNotFound(absolutePath)
    }

    guard let pdfDocument = PDFDocument(url: url) else {
      throw VisionError.imageLoadFailed("Failed to load PDF: \(input.pdf_path)")
    }

    var result: [String: Any] = [
      "page_count": pdfDocument.pageCount,
      "path": absolutePath,
    ]

    // Get first page dimensions
    if let firstPage = pdfDocument.page(at: 0) {
      let bounds = firstPage.bounds(for: .mediaBox)
      result["page_width_points"] = bounds.width
      result["page_height_points"] = bounds.height
      // Convert to inches (72 points per inch)
      result["page_width_inches"] = bounds.width / 72.0
      result["page_height_inches"] = bounds.height / 72.0
    }

    // Check if PDF is encrypted
    result["is_encrypted"] = pdfDocument.isEncrypted
    result["is_locked"] = pdfDocument.isLocked

    return result
  }
}

// MARK: - Plugin Context & Tools Registry

private class PluginContext {
  private let tools: [String: (String) -> String]

  init() {
    let detectText = DetectTextTool()
    let detectDocument = DetectDocumentTool()
    let detectBarcodes = DetectBarcodesTool()
    let detectFaces = DetectFacesTool()
    let detectRectangles = DetectRectanglesTool()
    let classifyImage = ClassifyImageTool()
    let detectHorizon = DetectHorizonTool()
    let detectBodyPose = DetectBodyPoseTool()
    let detectHandPose = DetectHandPoseTool()
    let detectAnimals = DetectAnimalsTool()
    let blurFaces = BlurFacesTool()
    let autoCrop = AutoCropTool()
    let generateSaliencyMap = GenerateSaliencyMapTool()
    let removeBackground = RemoveBackgroundTool()
    let getPDFInfo = GetPDFInfoTool()

    tools = [
      detectText.name: detectText.run,
      detectDocument.name: detectDocument.run,
      detectBarcodes.name: detectBarcodes.run,
      detectFaces.name: detectFaces.run,
      detectRectangles.name: detectRectangles.run,
      classifyImage.name: classifyImage.run,
      detectHorizon.name: detectHorizon.run,
      detectBodyPose.name: detectBodyPose.run,
      detectHandPose.name: detectHandPose.run,
      detectAnimals.name: detectAnimals.run,
      blurFaces.name: blurFaces.run,
      autoCrop.name: autoCrop.run,
      generateSaliencyMap.name: generateSaliencyMap.run,
      removeBackground.name: removeBackground.run,
      getPDFInfo.name: getPDFInfo.run,
    ]
  }

  func invoke(toolId: String, payload: String) -> String {
    tools[toolId]?(payload) ?? Envelope.failure(.notFound, "Unknown tool: \(toolId)")
  }
}

// MARK: - C ABI

private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

private struct osr_plugin_api {
  var free_string: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
  var `init`: (@convention(c) () -> osr_plugin_ctx_t?)?
  var destroy: (@convention(c) (osr_plugin_ctx_t?) -> Void)?
  var get_manifest: (@convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?)?
  var invoke:
    (
      @convention(c) (
        osr_plugin_ctx_t?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
      ) -> UnsafePointer<CChar>?
    )?
}

private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  strdup(s).map { UnsafePointer($0) }
}

// MARK: - Manifest

/// File-scope manifest JSON embedded in the dylib and returned by `get_manifest`.
/// Exposed as `internal` (not `private`) so unit tests can parse it via
/// `@testable import osaurus_vision`.
let visionManifestJSON = """
  {
    "plugin_id": "osaurus.vision",
    "name": "Vision",
    "version": "0.1.0",
    "description": "macOS Vision framework integration for image analysis, text detection, face detection, background removal, and more",
    "license": "MIT",
    "authors": [],
    "min_macos": "15.0",
    "min_osaurus": "0.5.0",
    "capabilities": {
      "tools": [
        {
          "id": "detect_text",
          "description": "Detect and recognize text in an image or PDF using OCR. Returns detected text blocks with bounding boxes and confidence scores.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image or PDF file (relative to working directory or absolute)"},
              "recognition_level": {"type": "string", "enum": ["accurate", "fast"], "description": "Recognition accuracy level. Default: accurate"},
              "languages": {"type": "array", "items": {"type": "string"}, "description": "Language codes to recognize (e.g., ['en-US', 'fr-FR'])"},
              "page": {"type": "integer", "description": "PDF page number (1-indexed). Default: 1"},
              "dpi": {"type": "integer", "description": "PDF render resolution in DPI. Default: 300"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_document",
          "description": "Detect document boundaries in an image or PDF. Returns corner points for perspective correction.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image or PDF file"},
              "page": {"type": "integer", "description": "PDF page number (1-indexed). Default: 1"},
              "dpi": {"type": "integer", "description": "PDF render resolution in DPI. Default: 300"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_barcodes",
          "description": "Detect and decode barcodes and QR codes in an image or PDF.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image or PDF file"},
              "symbologies": {"type": "array", "items": {"type": "string"}, "description": "Barcode types: qr, aztec, code128, code39, code93, datamatrix, ean8, ean13, itf14, pdf417, upce"},
              "page": {"type": "integer", "description": "PDF page number (1-indexed). Default: 1"},
              "dpi": {"type": "integer", "description": "PDF render resolution in DPI. Default: 300"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_faces",
          "description": "Detect faces in an image. Optionally includes facial landmarks (eyes, nose, mouth, face contour).",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image file"},
              "include_landmarks": {"type": "boolean", "description": "Include facial landmarks. Default: false"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_rectangles",
          "description": "Detect rectangular shapes in an image. Useful for finding documents, cards, screens.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image file"},
              "max_observations": {"type": "integer", "description": "Maximum rectangles to detect. Default: 10"},
              "min_aspect_ratio": {"type": "number", "description": "Minimum aspect ratio. Default: 0.0"},
              "max_aspect_ratio": {"type": "number", "description": "Maximum aspect ratio. Default: 1.0"},
              "min_confidence": {"type": "number", "description": "Minimum confidence (0-1). Default: 0.0"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "classify_image",
          "description": "Classify an image using Apple's built-in classifier. Returns labels with confidence scores.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image file"},
              "max_results": {"type": "integer", "description": "Maximum results to return. Default: 10"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_horizon",
          "description": "Detect the horizon angle in an image. Useful for auto-rotating tilted photos.",
          "parameters": {
            "type": "object",
            "properties": {"image_path": {"type": "string", "description": "Path to the image file"}},
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_body_pose",
          "description": "Detect human body poses. Returns 19 joint positions for each detected person.",
          "parameters": {
            "type": "object",
            "properties": {"image_path": {"type": "string", "description": "Path to the image file"}},
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_hand_pose",
          "description": "Detect hand poses. Returns finger joint positions and hand chirality (left/right).",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the image file"},
              "max_hands": {"type": "integer", "description": "Maximum hands to detect. Default: 2"}
            },
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "detect_animals",
          "description": "Detect animals (cats and dogs) in an image with labels and bounding boxes.",
          "parameters": {
            "type": "object",
            "properties": {"image_path": {"type": "string", "description": "Path to the image file"}},
            "required": ["image_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        },
        {
          "id": "blur_faces",
          "description": "Detect and blur all faces in an image for privacy protection.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the input image"},
              "output_path": {"type": "string", "description": "Path to save the output image"},
              "blur_radius": {"type": "number", "description": "Blur intensity. Default: 30"}
            },
            "required": ["image_path", "output_path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "auto_crop",
          "description": "Automatically crop an image to focus on the most salient region.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the input image"},
              "output_path": {"type": "string", "description": "Path to save the cropped image"},
              "aspect_ratio": {"type": "string", "description": "Target aspect ratio (e.g., '16:9', '1:1')"},
              "padding": {"type": "number", "description": "Padding around salient region (0-1). Default: 0.1"}
            },
            "required": ["image_path", "output_path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "generate_saliency_map",
          "description": "Generate a visual saliency heatmap showing areas of interest.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the input image"},
              "output_path": {"type": "string", "description": "Path to save the saliency map"},
              "type": {"type": "string", "enum": ["attention", "objectness"], "description": "Saliency type. Default: attention"}
            },
            "required": ["image_path", "output_path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "remove_background",
          "description": "Remove the background from an image, keeping only the foreground. Outputs transparent PNG.",
          "parameters": {
            "type": "object",
            "properties": {
              "image_path": {"type": "string", "description": "Path to the input image"},
              "output_path": {"type": "string", "description": "Path to save output (saved as PNG)"}
            },
            "required": ["image_path", "output_path"]
          },
          "requirements": [],
          "permission_policy": "ask"
        },
        {
          "id": "get_pdf_info",
          "description": "Get information about a PDF file including page count, dimensions, and encryption status. Use this before processing PDFs to determine how many pages exist.",
          "parameters": {
            "type": "object",
            "properties": {
              "pdf_path": {"type": "string", "description": "Path to the PDF file"}
            },
            "required": ["pdf_path"]
          },
          "requirements": [],
          "permission_policy": "auto"
        }
      ]
    }
  }
  """

// MARK: - API Implementation

nonisolated(unsafe) private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in
    if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
  }

  api.`init` = {
    Unmanaged.passRetained(PluginContext()).toOpaque()
  }

  api.destroy = { ctxPtr in
    guard let ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  }

  api.get_manifest = { _ in makeCString(visionManifestJSON) }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr, let typePtr, let idPtr, let payloadPtr else { return nil }

    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    guard type == "tool" else {
      return makeCString(Envelope.failure(.invalidArgs, "Unknown capability type: \(type)"))
    }

    return makeCString(ctx.invoke(toolId: id, payload: payload))
  }

  return api
}()

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  UnsafeRawPointer(&api)
}
