// Offscreen WKWebView screenshotter for mascot.html README assets.
// usage: swift snap.swift <html> <out.png> [pose] [delaySeconds] [skin]
import Cocoa
import WebKit

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: snap.swift html out.png [pose] [delay]"); exit(1) }
let htmlPath = args[1], outPath = args[2]
let poseArg = args.count > 3 ? args[3] : ""
let delay = args.count > 4 ? (Double(args[4]) ?? 2.5) : 2.5
let skinArg = args.count > 5 ? args[5] : ""

let W: CGFloat = 170, H: CGFloat = 200

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// parked far offscreen; still "ordered in" so WebKit renders it
let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: W, height: H),
                      styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = .clear
window.isOpaque = false

let config = WKWebViewConfiguration()
// offscreen views clamp DOM timers to 1 Hz and freeze animation clocks;
// the pose choreography needs real timing
config.preferences.setValue(false, forKey: "hiddenPageDOMTimerThrottlingEnabled")

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H), configuration: config)
web.setValue(false, forKey: "drawsBackground")
web.setValue(false, forKey: "windowOcclusionDetectionEnabled")
window.contentView = web
window.orderFrontRegardless()

final class Snapper: NSObject, WKNavigationDelegate {
    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        // bake a dark backdrop so the PNG looks right on any GitHub theme
        w.evaluateJavaScript("document.body.style.background='#17181a'", completionHandler: nil)
        if !skinArg.isEmpty {
            w.evaluateJavaScript("mascot.setSkin('\(skinArg)', false)", completionHandler: nil)
        }
        if !poseArg.isEmpty {
            let js = poseArg == "sleep" ? "mascot.setAwake(false)" : "mascot.play('\(poseArg)')"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                w.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = NSRect(x: 0, y: 0, width: W, height: H)
            cfg.snapshotWidth = NSNumber(value: 510)   // 3x
            w.takeSnapshot(with: cfg) { image, error in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write("snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
                    exit(1)
                }
                try? png.write(to: URL(fileURLWithPath: outPath))
                print("wrote \(outPath)")
                exit(0)
            }
        }
    }
}

let snapper = Snapper()
web.navigationDelegate = snapper
let url = URL(fileURLWithPath: htmlPath)
web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
app.run()
