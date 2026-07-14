#!/usr/bin/env swift
//
// Mascot — a desktop pet that keeps the Mac awake.
// Ships three switchable skins: Clawd (the Claude Code mascot), a gradient
// cloud inspired by the Codex mark, and a pixel cube inspired by the
// Cursor mark.
//
// A borderless floating window hosts mascot.html (the pixel art and
// behavior engine). This file owns everything native:
//   * the IOKit display-sleep assertion (PowerManager)
//   * the tight, click-through-aware window (mouse-location polling flips
//     ignoresMouseEvents so only Clawd's actual body catches the cursor)
//   * the menu bar item (keep-awake toggle, say hi, reset position,
//     launch at login, quit)
//   * position persistence and the pointer/drag feeds that make the
//     mascot's eyes track the cursor and its body tilt while dragged.
//
// Runs both compiled (build.sh -> Mascot.app) and interpreted (start.command).
//
import Cocoa
import WebKit
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Resources

// Resolve mascot.html — app bundle Resources first (.app), then next to
// the script (dev mode)
let htmlURL: URL = {
    if let bundled = Bundle.main.url(forResource: "mascot", withExtension: "html") {
        return bundled
    }
    let scriptPath = CommandLine.arguments[0]
    let scriptDir  = (scriptPath as NSString).deletingLastPathComponent
    let htmlPath   = (scriptDir as NSString).appendingPathComponent("mascot.html")
    return URL(fileURLWithPath: htmlPath)
}()

// MARK: - Power

/// Owns the IOKit assertion that keeps the display (and therefore the
/// lock screen) at bay while the mascot is on duty.
final class PowerManager {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isEnabled = false

    func enable() {
        guard !isEnabled else { return }
        // Note: must use NSString (toll-free bridged) - Swift 6 rejects direct String->CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as NSString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Clawd is keeping the Mac awake" as NSString,
            &assertionID
        )
        isEnabled = (result == kIOReturnSuccess)
        if !isEnabled {
            FileHandle.standardError.write(
                "warning: IOPMAssertion failed (\(result)) - display may sleep\n".data(using: .utf8)!
            )
        }
    }

    func disable() {
        guard isEnabled else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isEnabled = false
    }
}

// MARK: - Window / web view

/// Borderless windows refuse key status by default; Clawd's close button
/// still wants clicks to land on the first try.
final class MascotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class MascotWebView: WKWebView {
    /// Decides whether a mouse-down should drag the window (Clawd's body)
    /// or go to the page (the close button). Set by the app delegate.
    var isDragPoint: ((NSEvent) -> Bool)?
    var onPoke: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // WKWebView ignores `-webkit-app-region: drag` and reports
    // mouseDownCanMoveWindow = false, so isMovableByWindowBackground never
    // engages for web content. Window dragging is implemented natively:
    // a short tracking loop turns small, quick presses into pokes and
    // anything that moves into a real window drag.
    override func mouseDown(with event: NSEvent) {
        guard isDragPoint?(event) == true, let window else {
            super.mouseDown(with: event)
            return
        }
        let start = event.locationInWindow
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if next.type == .leftMouseUp {
                onPoke?()
                return
            }
            if hypot(next.locationInWindow.x - start.x,
                     next.locationInWindow.y - start.y) > 3 {
                window.performDrag(with: event)
                return
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKScriptMessageHandler, WKNavigationDelegate {

    // Window content size — mascot.html lays out a 154x154 sprite stage
    // plus the label underneath.
    private let winSize = NSSize(width: 170, height: 178)
    private let screenMargin: CGFloat = 24

    // Mascot skins, mirrored in mascot.html's SKINS table.
    private struct Skin {
        let id: String
        let title: String
        let glyph: String        // menu bar symbol while this skin is active
        let trickTitle: String   // per-skin trick in the menu
        let trick: String        // mascot.play(...) name
    }
    private let skins = [
        Skin(id: "clawd",  title: "Clawd",  glyph: "✻", trickTitle: "Coffee break", trick: "coffee"),
        Skin(id: "codex",  title: "Codex",  glyph: "☁", trickTitle: "Make it rain", trick: "rain"),
        Skin(id: "cursor", title: "Cursor", glyph: "▮", trickTitle: "Tab, tab",     trick: "tabtab"),
    ]
    private let skinKey = "mascotSkin"
    private var activeSkin: Skin {
        let saved = UserDefaults.standard.string(forKey: skinKey)
        return skins.first { $0.id == saved } ?? skins[0]
    }

    private var window: MascotWindow!
    private var webView: MascotWebView!
    private var statusItem: NSStatusItem!
    private var awakeMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem?
    private var trickMenuItem: NSMenuItem!
    private var skinMenuItems: [NSMenuItem] = []

    private let power = PowerManager()

    // Hit zones reported by mascot.html (CSS coordinates, top-left origin).
    private var bodyZone: CGRect?
    private var closeZone: CGRect?
    private var lastOverBody = Date.distantPast

    private var pollTimer: Timer?
    private var pageReady = false
    private var lastSentPointer = CGPoint(x: -9999, y: -9999)
    private var pointerWasNear = false

    private var lastOrigin = CGPoint.zero
    private var isRepositioning = false      // squelch windowDidMove during programmatic moves
    private var saveTimer: Timer?

    private let originXKey = "mascotOriginX"
    private let originYKey = "mascotOriginY"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // v2.3.0: the "openai" skin became "codex"
        if UserDefaults.standard.string(forKey: skinKey) == "openai" {
            UserDefaults.standard.set("codex", forKey: skinKey)
        }
        power.enable()
        buildWindow()
        buildStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        power.disable()
    }

    // MARK: Window

    private func buildWindow() {
        let frame = NSRect(origin: restoredOrigin(), size: winSize)

        window = MascotWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // dragging is driven by MascotWebView.mouseDown, not the background
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true     // click-through until the cursor is on Clawd
        window.delegate = self
        lastOrigin = frame.origin

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "quit")
        config.userContentController.add(self, name: "hitRect")

        webView = MascotWebView(
            frame: NSRect(origin: .zero, size: frame.size),
            configuration: config
        )
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.isDragPoint = { [weak self] event in
            guard let self else { return false }
            let loc = event.locationInWindow
            let css = CGPoint(x: loc.x, y: self.window.frame.height - loc.y)
            let onBody = self.bodyZone?.contains(css) ?? false
            let onClose = self.closeZone?.insetBy(dx: -6, dy: -6).contains(css) ?? false
            return onBody && !onClose
        }
        webView.onPoke = { [weak self] in self?.js("mascot.poke()") }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())

        window.contentView = webView
        window.orderFrontRegardless()        // show without stealing focus
    }

    private func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let v = screen.visibleFrame
        return CGPoint(x: v.maxX - winSize.width - screenMargin,
                       y: v.maxY - winSize.height - screenMargin)
    }

    private func restoredOrigin() -> CGPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: originXKey) != nil else { return defaultOrigin() }
        let candidate = NSRect(x: d.double(forKey: originXKey),
                               y: d.double(forKey: originYKey),
                               width: winSize.width, height: winSize.height)
        // Only restore somewhere actually visible (displays change).
        for screen in NSScreen.screens {
            let overlap = candidate.intersection(screen.visibleFrame)
            if overlap.width > 60 && overlap.height > 60 { return candidate.origin }
        }
        return defaultOrigin()
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.systemFont(ofSize: 14)
        }

        let menu = NSMenu()

        awakeMenuItem = NSMenuItem(title: "Keep Mac awake",
                                   action: #selector(toggleAwake), keyEquivalent: "")
        awakeMenuItem.target = self
        awakeMenuItem.state = .on
        menu.addItem(awakeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // the skin switcher
        let mascotMenu = NSMenu()
        skinMenuItems = skins.map { skin in
            let item = NSMenuItem(title: skin.title, action: #selector(switchSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skin.id
            mascotMenu.addItem(item)
            return item
        }
        let mascotItem = NSMenuItem(title: "Mascot", action: nil, keyEquivalent: "")
        mascotItem.submenu = mascotMenu
        menu.addItem(mascotItem)

        let hi = NSMenuItem(title: "Say hi", action: #selector(sayHi), keyEquivalent: "")
        hi.target = self
        menu.addItem(hi)

        trickMenuItem = NSMenuItem(title: "", action: #selector(playTrick), keyEquivalent: "")
        trickMenuItem.target = self
        menu.addItem(trickMenuItem)

        menu.addItem(NSMenuItem.separator())

        let recenter = NSMenuItem(title: "Reset position",
                                  action: #selector(resetPosition), keyEquivalent: "r")
        recenter.target = self
        menu.addItem(recenter)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Launch at login",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
            loginMenuItem = login
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Mascot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        applySkinChrome()
    }

    /// Menu bar glyph, radio checkmarks, trick title — everything that
    /// reflects the active skin natively.
    private func applySkinChrome() {
        let skin = activeSkin
        statusItem.button?.title = skin.glyph
        statusItem.button?.toolTip = power.isEnabled
            ? "\(skin.title) — keeping your Mac awake"
            : "\(skin.title) — on a break (display may sleep)"
        trickMenuItem.title = skin.trickTitle
        skinMenuItems.forEach { $0.state = ($0.representedObject as? String) == skin.id ? .on : .off }
    }

    // MARK: Menu actions

    @objc private func toggleAwake() {
        if power.isEnabled { power.disable() } else { power.enable() }
        awakeMenuItem.state = power.isEnabled ? .on : .off
        statusItem.button?.alphaValue = power.isEnabled ? 1.0 : 0.45
        applySkinChrome()
        js("mascot.setAwake(\(power.isEnabled))")
    }

    @objc private func sayHi() { js("mascot.wave()") }
    @objc private func playTrick() { js("mascot.play('\(activeSkin.trick)')") }

    @objc private func switchSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != activeSkin.id else { return }
        UserDefaults.standard.set(id, forKey: skinKey)
        js("mascot.setSkin('\(id)')")
        applySkinChrome()
    }

    @objc private func resetPosition() {
        isRepositioning = true
        window.setFrameOrigin(defaultOrigin())
        lastOrigin = window.frame.origin
        isRepositioning = false
        persistOrigin()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error)")
        }
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: JS bridge

    private func js(_ script: String) {
        guard pageReady else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        js("mascot.setSkin('\(activeSkin.id)', false)")
        js("mascot.setAwake(\(power.isEnabled))")
        startMousePolling()
    }

    func userContentController(_ ucc: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "quit":
            NSApp.terminate(nil)
        case "hitRect":
            guard let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let zones = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
            else { return }
            bodyZone  = rect(from: zones["body"])
            closeZone = rect(from: zones["close"])
        default:
            break
        }
    }

    private func rect(from dict: [String: Double]?) -> CGRect? {
        guard let d = dict, let x = d["x"], let y = d["y"], let w = d["w"] ?? d["width"],
              let h = d["h"] ?? d["height"] else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Hitbox + pointer feed
    //
    // A 20 Hz poll of the global mouse location drives two things:
    //  1. ignoresMouseEvents — the window only catches the cursor while it
    //     is over Clawd's body (or the revealed close button), so the rest
    //     of the window frame never blocks clicks. This is the fix for the
    //     old "invisible box in front of my mouse" problem.
    //  2. mascot.setPointer(...) — eye tracking and hover reactions.

    private func startMousePolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollMouse()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollMouse() {
        let loc = NSEvent.mouseLocation          // screen coords, bottom-left origin
        let f = window.frame
        let css = CGPoint(x: loc.x - f.minX, y: f.maxY - loc.y)   // page coords, top-left origin

        let inBody = bodyZone?.contains(css) ?? false
        if inBody { lastOverBody = Date() }
        let closeGrace = Date().timeIntervalSince(lastOverBody) < 0.9
        let inClose = closeZone.map { $0.insetBy(dx: -6, dy: -6).contains(css) } ?? false

        // Never flip mid-drag/mid-click — that would drop the event stream.
        if NSEvent.pressedMouseButtons & 1 == 0 {
            window.ignoresMouseEvents = !(inBody || (closeGrace && inClose))
        }

        // Feed the eyes while the cursor is anywhere near the pet.
        let center = CGPoint(x: f.midX, y: f.midY)
        let near = hypot(loc.x - center.x, loc.y - center.y) < 480
        if near {
            if hypot(css.x - lastSentPointer.x, css.y - lastSentPointer.y) >= 1 {
                lastSentPointer = css
                js("mascot.setPointer(\(Int(css.x)), \(Int(css.y)))")
            }
        } else if pointerWasNear {
            js("mascot.setPointer(-99999, -99999)")   // out of sight, eyes wander freely
        }
        pointerWasNear = near
    }

    // MARK: Drag feedback + persistence

    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning else { return }
        let origin = window.frame.origin
        let dx = origin.x - lastOrigin.x
        let dy = origin.y - lastOrigin.y
        lastOrigin = origin
        if abs(dx) + abs(dy) > 0.5 {
            js("mascot.windowMoved(\(Int(dx)), \(Int(dy)))")
        }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.persistOrigin()
        }
    }

    private func persistOrigin() {
        let d = UserDefaults.standard
        d.set(Double(window.frame.origin.x), forKey: originXKey)
        d.set(Double(window.frame.origin.y), forKey: originYKey)
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only: no Dock icon, no ⌘Tab
let delegate = AppDelegate()
app.delegate = delegate
app.run()
