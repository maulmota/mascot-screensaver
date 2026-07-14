// Report frame pacing at the start of a video: largest gap and fps
// over the first N seconds.
// usage: swift gaps.swift <in.mp4> [windowSeconds]
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: gaps.swift in.mp4 [windowSeconds]"); exit(1) }
let window = args.count > 2 ? (Double(args[2]) ?? 4.0) : 4.0
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))

guard let track = asset.tracks(withMediaType: .video).first,
      let reader = try? AVAssetReader(asset: asset) else { exit(1) }
let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
reader.add(output)
reader.startReading()

var times: [Double] = []
while let sample = output.copyNextSampleBuffer() {
    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    if t > window { break }
    times.append(t)
}
times.sort()
var maxGap = 0.0, gapAt = 0.0
for i in 1..<times.count {
    let g = times[i] - times[i-1]
    if g > maxGap { maxGap = g; gapAt = times[i-1] }
}
let fps = Double(times.count) / window
print(String(format: "first %.0fs: %d frames (%.1f fps), largest gap %.0f ms at t=%.2fs",
             window, times.count, fps, maxGap * 1000, gapAt))
