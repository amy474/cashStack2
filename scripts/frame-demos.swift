// Frames each raw Simulator recording in an iPhone 17 Pro and writes an MP4
// and a GIF. Only AVFoundation, CoreGraphics and ImageIO: nothing to install.
//
//   swift scripts/frame-demos.swift <work-dir> <out-dir> test1SwipeToPay ...
//
// <work-dir>/raw/<test>.mp4 is the recording, <work-dir>/markers/<test>.rec
// the wall-clock time it started, and <work-dir>/markers/<test>.txt the
// "start"/"end" times the UI test wrote. PEEK=1 also dumps a still every
// half second to <work-dir>/peek/<test>/ for checking the cut.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Clips

struct Clip {
    let test: String
    let name: String
    /// Seconds to skip after the "start" mark, and the clip's length.
    var lead: Double = 0
    var length: Double
    var speed: Double? = nil
    /// Stretches of the take, in seconds after the cut starts, to run through
    /// faster: the beat while XCUITest finds the next thing to touch.
    var ramps: [(from: Double, to: Double, speed: Double)] = []
}

let catalogue: [String: Clip] = [
    "test1SwipeToPay":     Clip(test: "test1SwipeToPay",     name: "1-swipe-to-pay",     length: 5),
    "test2Organise":       Clip(test: "test2Organise",       name: "2-organise",         length: 5),
    "test3Split":          Clip(test: "test3Split",          name: "3-split",            lead: 0.4, length: 3),
    "test4MoneyJars":      Clip(test: "test4MoneyJars",      name: "4-money-jars",       length: 10),
    "test5TipJar":         Clip(test: "test5TipJar",         name: "5-tip-jar",          lead: 0.4, length: 5.5,
                                speed: 1.25, ramps: [(0.8, 1.9, 3)]),
    "test6SwitchAccounts": Clip(test: "test6SwitchAccounts", name: "6-switch-accounts",  length: 5),
]

// MARK: The phone, in screen pixels (iPhone 17 Pro, 402 × 874 pt at 3×)

let screenW: CGFloat = 1206, screenH: CGFloat = 2622
let screenRadius: CGFloat = 186          // 62pt
let blackBezel: CGFloat = 46
let metalBand: CGFloat = 20
let buttonDepth: CGFloat = 11
let margin: CGFloat = 90                 // around the phone, for the shadow

let bodyW = screenW + 2 * (blackBezel + metalBand)
let bodyH = screenH + 2 * (blackBezel + metalBand)
let canvasW = bodyW + 2 * (margin + buttonDepth)
let canvasH = bodyH + 2 * margin
let bodyRect = CGRect(x: margin + buttonDepth, y: margin, width: bodyW, height: bodyH)
let screenRect = bodyRect.insetBy(dx: blackBezel + metalBand, dy: blackBezel + metalBand)

let videoScale: CGFloat = 0.75
let gifWidth: CGFloat = 360
let videoFPS: Int32 = 30
let gifFPS = 20

let background = CGColor(srgbRed: 0.945, green: 0.941, blue: 0.929, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// Everything behind the screen: ground, shadow, buttons, the metal band and
/// the black glass border. Drawn once. CoreGraphics is y-up, so "top" is maxY.
func drawUnderlay(_ c: CGContext) {
    c.setFillColor(background)
    c.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

    let outerRadius = screenRadius + blackBezel + metalBand
    let body = roundedPath(bodyRect, outerRadius)

    // Soft shadow on the ground.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: rgb(0x000000, 0.28))
    c.addPath(body); c.setFillColor(rgb(0x2C2C2E)); c.fillPath()
    c.restoreGState()

    // Buttons, measured from the top of the phone in points.
    func button(left: Bool, fromTop: CGFloat, length: CGFloat) {
        let y = bodyRect.maxY - (fromTop + length) * 3
        let x = left ? bodyRect.minX - buttonDepth : bodyRect.maxX - 6
        let rect = CGRect(x: x, y: y, width: buttonDepth + 6, height: length * 3)
        c.saveGState()
        c.addPath(roundedPath(rect, 7)); c.clip()
        let g = CGGradient(colorsSpace: space, colors: [rgb(0x1F2023), rgb(0x6A6C72), rgb(0x2A2B2F)] as CFArray,
                           locations: [0, 0.5, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        c.restoreGState()
    }
    button(left: true, fromTop: 150, length: 34)     // Action button
    button(left: true, fromTop: 222, length: 62)     // Volume up
    button(left: true, fromTop: 300, length: 62)     // Volume down
    button(left: false, fromTop: 250, length: 100)   // Side button
    button(left: false, fromTop: 560, length: 56)    // Camera Control

    // The metal band: a dark titanium edge with a highlight that runs round it.
    c.saveGState()
    c.addPath(body); c.clip()
    let metal = CGGradient(colorsSpace: space,
                           colors: [rgb(0x5B5D63), rgb(0x2B2C30), rgb(0x8B8D93), rgb(0x2B2C30), rgb(0x4A4C52)] as CFArray,
                           locations: [0, 0.22, 0.5, 0.78, 1])!
    c.drawLinearGradient(metal, start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                         end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY), options: [])
    c.restoreGState()

    // A fine bright line just inside the band's outer edge.
    c.addPath(roundedPath(bodyRect.insetBy(dx: 2.5, dy: 2.5), outerRadius - 2.5))
    c.setStrokeColor(rgb(0xC8CACF, 0.55)); c.setLineWidth(2); c.strokePath()

    // The black glass border, with the faintest lift at its edge.
    let glass = bodyRect.insetBy(dx: metalBand, dy: metalBand)
    c.addPath(roundedPath(glass, screenRadius + blackBezel))
    c.setFillColor(rgb(0x050506)); c.fillPath()
    c.addPath(roundedPath(glass.insetBy(dx: 1.5, dy: 1.5), screenRadius + blackBezel - 1.5))
    c.setStrokeColor(rgb(0x3A3A3E, 0.9)); c.setLineWidth(2); c.strokePath()
}

/// Over the screen: the Dynamic Island, which a Simulator recording leaves out.
func drawOverlay(_ c: CGContext) {
    let w: CGFloat = 375, h: CGFloat = 111
    let island = CGRect(x: screenRect.midX - w / 2, y: screenRect.maxY - 33 - h, width: w, height: h)
    c.addPath(roundedPath(island, h / 2)); c.setFillColor(rgb(0x000000)); c.fillPath()
    // The front camera, just visible in the black.
    let lens = CGRect(x: island.maxX - h * 0.5 - 22, y: island.midY - 22, width: 44, height: 44)
    c.addEllipse(in: lens); c.setFillColor(rgb(0x0B0F1A)); c.fillPath()
    c.addEllipse(in: lens.insetBy(dx: 12, dy: 12)); c.setFillColor(rgb(0x1A2238)); c.fillPath()
}

let underlay: CGImage = { let c = makeContext(Int(canvasW), Int(canvasH)); drawUnderlay(c); return c.makeImage()! }()

func compose(screen: CGImage?, into c: CGContext, scale: CGFloat) {
    c.saveGState()
    c.interpolationQuality = .high
    c.scaleBy(x: scale, y: scale)
    c.draw(underlay, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
    if let screen {
        c.saveGState()
        c.addPath(roundedPath(screenRect, screenRadius)); c.clip()
        c.draw(screen, in: screenRect)
        c.restoreGState()
    }
    drawOverlay(c)
    c.restoreGState()
}

// MARK: Reading the recording

func image(from buffer: CVPixelBuffer) -> CGImage {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                        width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    return ctx.makeImage()!
}

func seconds(_ path: String) -> Double? {
    (try? String(contentsOfFile: path, encoding: .utf8)).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

func marks(_ path: String) -> [String: Double] {
    var out: [String: Double] = [:]
    for line in ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n") {
        let parts = line.split(separator: " ")
        if parts.count == 2, let t = Double(parts[1]) { out[String(parts[0])] = t }
    }
    return out
}

func savePNG(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: One clip

func render(_ clip: Clip, work: String, out: String) throws {
    let raw = URL(fileURLWithPath: "\(work)/raw/\(clip.test).mp4")
    guard let recStart = seconds("\(work)/markers/\(clip.test).rec"),
          let start = marks("\(work)/markers/\(clip.test).txt")["start"] else {
        print("  \(clip.test): no markers, skipped"); return
    }
    let end = marks("\(work)/markers/\(clip.test).txt")["end"]
    let from = start - recStart + clip.lead
    // A take that ran a little long is played a touch faster, up to 1.2×,
    // rather than losing its ending. SPEED_<test> overrides.
    let marked = (end ?? start + clip.length) - start - clip.lead
    let speed = ProcessInfo.processInfo.environment["SPEED_\(clip.test)"].flatMap(Double.init) ?? clip.speed
        ?? min(max(marked / clip.length, 1), 1.2)
    print(String(format: "  %@: marked %.2fs, cutting %.2fs at %.2f×", clip.name, marked, clip.length, speed))

    let asset = AVURLAsset(url: raw)
    let track = asset.tracks(withMediaType: .video).first!
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    reader.add(output)
    reader.startReading()

    // The recording only writes a frame when the screen changes, so walk it
    // and hold whichever frame was showing at each output tick.
    var firstPTS: Double?
    var current: CGImage?
    var pending: (Double, CGImage)?
    func frame(at t: Double) -> CGImage? {
        while true {
            if let (pts, img) = pending {
                if pts <= t { current = img; pending = nil } else { return current }
            }
            guard let sample = output.copyNextSampleBuffer() else { return current }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if firstPTS == nil { firstPTS = pts }
            pending = (pts - firstPTS!, image(from: buffer))
        }
    }

    // Writers.
    let vw = Int((canvasW * videoScale / 2).rounded()) * 2, vh = Int((canvasH * videoScale / 2).rounded()) * 2
    let mp4 = URL(fileURLWithPath: "\(out)/\(clip.name).mp4")
    try? FileManager.default.removeItem(at: mp4)
    let writer = try AVAssetWriter(outputURL: mp4, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: vw, AVVideoHeightKey: vh,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: vw, kCVPixelBufferHeightKey as String: vh
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let gw = Int(gifWidth), gh = Int((canvasH * gifWidth / canvasW).rounded())
    let gifURL = URL(fileURLWithPath: "\(out)/\(clip.name).gif")
    let gifFrames = Int(clip.length * Double(gifFPS))
    let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, gifFrames, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let gifFrameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(gifFPS),
                                                         kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(gifFPS)]] as CFDictionary

    let peekDir = "\(work)/peek/\(clip.test)"
    let peeking = ProcessInfo.processInfo.environment["PEEK"] != nil
    if peeking { try? FileManager.default.removeItem(atPath: peekDir); try? FileManager.default.createDirectory(atPath: peekDir, withIntermediateDirectories: true) }

    let total = Int(clip.length * Double(videoFPS))
    var nextGif = 0
    var rawT = 0.0
    for i in 0..<total {
        let t = Double(i) / Double(videoFPS)
        let screen = frame(at: from + rawT)
        rawT += (clip.ramps.first { rawT >= $0.from && rawT < $0.to }?.speed ?? speed) / Double(videoFPS)

        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: vw, height: vh, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        compose(screen: screen, into: ctx, scale: CGFloat(vw) / canvasW)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { usleep(2_000) }   // fine for a script
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: videoFPS))

        if nextGif < gifFrames, t + 1e-6 >= Double(nextGif) / Double(gifFPS) {
            let g = makeContext(gw, gh)
            compose(screen: screen, into: g, scale: CGFloat(gw) / canvasW)
            CGImageDestinationAddImage(gif, g.makeImage()!, gifFrameProps)
            nextGif += 1
        }
        if peeking, i % (Int(videoFPS) / 2) == 0 {
            let p = makeContext(500, Int(canvasH * 500 / canvasW))
            compose(screen: screen, into: p, scale: 500 / canvasW)
            savePNG(p.makeImage()!, String(format: "%@/%05.2f.png", peekDir, t))
        }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    reader.cancelReading()
    CGImageDestinationFinalize(gif)
    if writer.status != .completed { print("  \(clip.name): writer failed: \(String(describing: writer.error))") }
}

// MARK: Main

let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("usage: frame-demos.swift <work-dir> <out-dir> [test ...]"); exit(1)
}
let work = args[args.startIndex], out = args[args.startIndex + 1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let tests = args.count > 2 ? Array(args.dropFirst(2)) : catalogue.keys.sorted()
for test in tests {
    guard var clip = catalogue[test] else { print("unknown clip \(test)"); continue }
    if let lead = ProcessInfo.processInfo.environment["LEAD_\(test)"].flatMap(Double.init) { clip.lead = lead }
    if let length = ProcessInfo.processInfo.environment["LENGTH_\(test)"].flatMap(Double.init) { clip.length = length }
    try render(clip, work: work, out: out)
}
print("Wrote \(tests.count) clip(s) to \(out)")
