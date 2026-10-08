//
//  make-face-icon.swift
//  AgoyNotch
//
//  Turns a photo of a person into the AgoyNotch app icon: the person is kept, the
//  background becomes black, the crop is a square around the face, and the result is the
//  same 824 px rounded square (on a transparent 1024×1024 canvas) as Resources/AppIcon.png.
//
//  Uses only Apple frameworks (Vision, Core Image, Core Graphics, ImageIO) and runs
//  entirely on this Mac — the photo is never uploaded anywhere. Not part of the app:
//  scripts/build-app.sh compiles and runs it for `--face PHOTO`.
//
//  Usage: make-face-icon <photo> <output.png>
//

import Foundation
import CoreGraphics
import CoreVideo
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import ImageIO

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-face-icon <photo> <output.png>\n".utf8))
    exit(2)
}
let inputPath = args[1]
let outputPath = args[2]

// --- Load (JPEG / HEIC / PNG, EXIF orientation applied) ----------------------------------
guard let loaded = CIImage(contentsOf: URL(fileURLWithPath: inputPath),
                           options: [.applyOrientationProperty: true]) else {
    fail("cannot read image \(inputPath)")
}
let image = loaded.transformed(by: CGAffineTransform(translationX: -loaded.extent.origin.x,
                                                     y: -loaded.extent.origin.y))
let extent = image.extent
let W = extent.width
let H = extent.height
if min(W, H) < 256 {
    fail("photo too small (need ≥ 256 px on the short side)")
}

// --- Vision: largest face + person segmentation mask -------------------------------------
let ci = CIContext()
guard let visionInput = ci.createCGImage(image, from: extent) else {
    fail("cannot render image")
}

let face = VNDetectFaceRectanglesRequest()
let person = VNGeneratePersonSegmentationRequest()
person.qualityLevel = .accurate
person.outputPixelFormat = kCVPixelFormatType_OneComponent8

do {
    try VNImageRequestHandler(cgImage: visionInput, orientation: .up, options: [:]).perform([face, person])
} catch {
    fail("Vision failed: \(error.localizedDescription)")
}

guard let maskBuffer = person.results?.first?.pixelBuffer else {
    fail("no person found in the photo")
}

// Normalized bounding box, bottom-left origin (same y-up convention as CI / CG).
let faces: [VNFaceObservation] = face.results ?? []
let largestFace = faces.max { a, b in
    a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
}

// --- Square crop in image pixels (y-up) --------------------------------------------------
let side: CGFloat
let ox: CGFloat
let oy: CGFloat
if let box = largestFace?.boundingBox {
    let f = CGRect(x: box.origin.x * W, y: box.origin.y * H,
                   width: box.width * W, height: box.height * H)
    side = min(2.4 * max(f.width, f.height), min(W, H))
    // Nudge the centre down a little to include the chin and neck.
    let cx = f.midX
    let cy = f.midY - 0.15 * f.height
    ox = min(max(cx - side / 2, 0), W - side)
    oy = min(max(cy - side / 2, 0), H - side)
} else {
    side = min(W, H)
    ox = (W - side) / 2
    oy = H - side
}
let square = CGRect(x: ox, y: oy, width: side, height: side).integral

// --- Composite: person over black --------------------------------------------------------
let rawMask = CIImage(cvPixelBuffer: maskBuffer)
let scaledMask = rawMask.transformed(by: CGAffineTransform(scaleX: W / rawMask.extent.width,
                                                           y: H / rawMask.extent.height))

let blend = CIFilter.blendWithMask()
blend.inputImage = image
blend.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: extent)
blend.maskImage = scaledMask
guard let composite = blend.outputImage else {
    fail("cannot render image")
}

// Reject people-less photos (they would give an all-black icon). The CIAreaAverage output
// is a 1×1 image at the origin of `extent`, so render exactly `out.extent`.
let avg = CIFilter.areaAverage()
avg.inputImage = scaledMask
avg.extent = square
guard let out = avg.outputImage else { fail("no person found in the photo") }
var px = [UInt8](repeating: 0, count: 4)
ci.render(out, toBitmap: &px, rowBytes: 4, bounds: out.extent, format: .RGBA8, colorSpace: nil)
let mean = Double(px[0]) / 255   // R channel; nil colour space = no gamma re-encode
if mean < 0.02 { fail("no person found in the photo") }

guard let croppedCG = ci.createCGImage(composite.cropped(to: square), from: square) else {
    fail("cannot render image")
}

// --- Output: 1024×1024, transparent outside the 824 px rounded square --------------------
guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                          bytesPerRow: 0, space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("cannot render image")
}
ctx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.clip()
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(iconRect)
ctx.interpolationQuality = .high
ctx.draw(croppedCG, in: iconRect)

guard let cg = ctx.makeImage() else {
    fail("cannot render image")
}

let url = URL(fileURLWithPath: outputPath)
do {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
} catch {
    fail("cannot write \(outputPath)")
}
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fail("cannot write \(outputPath)")
}
CGImageDestinationAddImage(dest, cg, nil)
if !CGImageDestinationFinalize(dest) {
    fail("cannot write \(outputPath)")
}

print("Wrote \(outputPath)")
