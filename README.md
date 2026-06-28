# Vision

An Osaurus plugin (display name **Vision**, plugin id `osaurus.vision`) that provides macOS Vision framework capabilities for AI agents. Enables text detection, face analysis, background removal, pose detection, and more.

## Tools

### Detection Tools (Read-only)

| Tool | Description |
|------|-------------|
| `detect_text` | Detect and recognize text in images or PDFs using OCR |
| `detect_document` | Detect document boundaries in images or PDFs for perspective correction |
| `detect_barcodes` | Detect and decode barcodes and QR codes in images or PDFs |
| `detect_faces` | Detect faces with optional facial landmarks |
| `detect_rectangles` | Detect rectangular shapes (documents, cards, screens) |
| `classify_image` | Classify images using Apple's built-in classifier |
| `detect_horizon` | Detect horizon angle for auto-rotation |
| `detect_body_pose` | Detect human body poses (19 joint positions) |
| `detect_hand_pose` | Detect hand poses with finger joint positions |
| `detect_animals` | Detect cats and dogs with bounding boxes |

### Image Processing Tools

| Tool | Description |
|------|-------------|
| `blur_faces` | Automatically blur all faces in an image |
| `auto_crop` | Smart crop focusing on salient regions |
| `generate_saliency_map` | Generate attention/objectness heatmaps |
| `remove_background` | Remove background, output transparent PNG |

### Utility Tools

| Tool | Description |
|------|-------------|
| `get_pdf_info` | Get PDF metadata including page count, dimensions, and encryption status |

## Example Usage

```
# Detect text in a screenshot
detect_text(image_path: "screenshot.png")

# Remove background from a photo
remove_background(image_path: "photo.jpg", output_path: "photo_nobg.png")

# Blur faces for privacy
blur_faces(image_path: "group.jpg", output_path: "group_blurred.jpg", blur_radius: 40)

# Auto-crop to 16:9 aspect ratio
auto_crop(image_path: "photo.jpg", output_path: "cropped.jpg", aspect_ratio: "16:9")
```

### PDF Support

The `detect_text`, `detect_document`, and `detect_barcodes` tools support PDF files. Use `get_pdf_info` to inspect a PDF before processing.

```
# Get PDF information (page count, dimensions)
get_pdf_info(pdf_path: "document.pdf")
# Returns: { page_count: 10, page_width_inches: 8.5, page_height_inches: 11, ... }

# Extract text from a specific PDF page
detect_text(image_path: "document.pdf", page: 3)

# Extract text from all pages of a multi-page PDF
get_pdf_info(pdf_path: "document.pdf")  # First check page count
detect_text(image_path: "document.pdf", page: 1)
detect_text(image_path: "document.pdf", page: 2)
# ... etc

# Use higher DPI for better OCR accuracy on small text
detect_text(image_path: "document.pdf", page: 1, dpi: 600)

# Scan PDF for barcodes/QR codes
detect_barcodes(image_path: "shipping_label.pdf")
```

**PDF Parameters:**
- `page` - Page number (1-indexed). Default: 1
- `dpi` - Render resolution in DPI. Default: 300. Higher values improve accuracy but use more memory.

## Requirements

- macOS 15.0 or later
- Osaurus 0.5.0 or later

## Development

1. Build:
   ```bash
   swift build -c release
   ```

2. Extract manifest (to verify):
   ```bash
   osaurus manifest extract .build/release/libosaurus-vision.dylib
   ```
   
3. Package (for distribution):
   ```bash
   osaurus tools package osaurus.vision 0.1.0
   ```
   This creates `osaurus.vision-0.1.0.zip`.
   
4. Install locally:
   ```bash
   osaurus tools install ./osaurus.vision-0.1.0.zip
   ```
   
## Publishing

This project includes a GitHub Actions workflow (`.github/workflows/release.yml`) that
automatically builds and releases the plugin when you push a version tag.

To release:
```bash
git tag v0.1.0
git push origin v0.1.0
```

For manual publishing:

1. Package it with the correct naming convention:
   ```bash
   osaurus tools package <plugin_id> <version>
   ```
   The zip file MUST be named `<plugin_id>-<version>.zip`.
   
2. Host the zip file (e.g. GitHub Releases).

3. Create a registry entry JSON file for the central repository.

## License

MIT
