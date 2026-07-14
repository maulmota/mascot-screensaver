// Offscreen WKWebView -> H.264 video recorder (no screen capture involved).
// usage: swift record.swift <url> <out.mp4> <widthPt> <heightPt> <seconds>
import Cocoa
import WebKit
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 6 else { print("usage: record.swift url out.mp4 wPt hPt seconds"); exit(1) }
let urlArg = args[1], outPath = args[2]
let W = CGFloat(Double(args[3]) ?? 960)
let H = CGFloat(Double(args[4]) ?? 540)
let DURATION = Double(args[5]) ?? 50
let PXW = Int(W) * 2, PXH = Int(H) * 2

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: W, height: H),
                      styleMask: .borderless, backing: .buffered, defer: false)

let config = WKWebViewConfiguration()
config.preferences.setValue(false, forKey: "hiddenPageDOMTimerThrottlingEnabled")

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H), configuration: config)
web.setValue(false, forKey: "windowOcclusionDetectionEnabled")
window.contentView = web
window.orderFrontRegardless()

// ---- writer ----
try? FileManager.default.removeItem(atPath: outPath)
let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: outPath), fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: PXW,
    AVVideoHeightKey: PXH,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 12_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 60,
        AVVideoExpectedSourceFrameRateKey: 30,
    ],
])
input.expectsMediaDataInRealTime = true
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: PXW,
        kCVPixelBufferHeightKey as String: PXH,
    ])
writer.add(input)

func pixelBuffer(from cg: CGImage) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, PXW, PXH, kCVPixelFormatType_32ARGB,
                              [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                              &pb) == kCVReturnSuccess, let buf = pb else { return nil }
    CVPixelBufferLockBaseAddress(buf, [])
    defer { CVPixelBufferUnlockBaseAddress(buf, []) }
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                              width: PXW, height: PXH, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: PXW, height: PXH))
    return buf
}

var frames = 0
var frameIdx = 0
let FPS = 30.0
var t0 = 0.0
var lastLog = 0.0

func captureNext() {
    let cfg = WKSnapshotConfiguration()
    cfg.rect = NSRect(x: 0, y: 0, width: W, height: H)
    cfg.snapshotWidth = NSNumber(value: PXW / 2)   // points; produces 2x pixels
    let requested = CACurrentMediaTime()
    web.takeSnapshot(with: cfg) { image, error in
        let now = CACurrentMediaTime()
        let t = now - t0
        if t >= DURATION {
            input.markAsFinished()
            writer.finishWriting {
                print("done: \(frames) frames over \(String(format: "%.1f", t))s -> \(String(format: "%.1f", Double(frames) / t)) fps avg")
                exit(0)
            }
            return
        }
        if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let buf = pixelBuffer(from: cg) {
            // constant frame rate: fill every 1/30s slot up to now with
            // this capture, so playback never stutters over capture jitter
            while Double(frameIdx) / FPS <= t {
                if input.isReadyForMoreMediaData {
                    adaptor.append(buf, withPresentationTime:
                        CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(FPS)))
                    frames += 1
                }
                frameIdx += 1
            }
        }
        if t - lastLog > 5 { lastLog = t; print(String(format: "  %.0fs…", t)) }
        // pace toward ~30 fps
        let elapsed = CACurrentMediaTime() - requested
        let delay = max(0, 1.0 / 30 - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { captureNext() }
    }
}

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        // warm the snapshot pipeline with throwaway captures before recording
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: W, height: H)
        cfg.snapshotWidth = NSNumber(value: PXW / 2)
        var warmups = 10
        func warm() {
            web.takeSnapshot(with: cfg) { _, _ in
                warmups -= 1
                if warmups > 0 { warm(); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    writer.startWriting()
                    writer.startSession(atSourceTime: .zero)
                    t0 = CACurrentMediaTime()
                    captureNext()
                }
            }
        }
        warm()
    }
}
let nav = Nav()
web.navigationDelegate = nav
web.load(URLRequest(url: URL(string: urlArg)!))
app.run()
