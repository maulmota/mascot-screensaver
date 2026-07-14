// Dump PNG stills from a video for QC.
// usage: swift frames.swift <in.mp4> <outDir> <t1> <t2> ...
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: frames.swift in.mp4 outDir t1 t2 ..."); exit(1) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let outDir = args[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
gen.maximumSize = CGSize(width: 1280, height: 1280)

for a in args.dropFirst(3) {
    guard let t = Double(a) else { continue }
    do {
        let cg = try gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
        let rep = NSBitmapImageRep(cgImage: cg)
        if let png = rep.representation(using: .png, properties: [:]) {
            let path = "\(outDir)/t\(String(format: "%05.1f", t)).png"
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    } catch { print("t=\(t): \(error.localizedDescription)") }
}
