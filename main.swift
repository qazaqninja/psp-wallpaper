// PSP-style fluid wave live wallpaper.
// Build: swiftc -O main.swift -o PSPWallpaper -framework Cocoa -framework MetalKit
// Run:   ./PSPWallpaper &     Stop: menu bar wave icon -> Quit (or kill it).
// Customize: menu bar wave icon -> Settings, or edit config.json (live reload).

import Cocoa
import MetalKit
import SwiftUI
import Combine

let configPath: String = {
    let legacy = NSString(string: "~/psp-wallpaper/config.json").expandingTildeInPath
    if FileManager.default.fileExists(atPath: legacy) { return legacy }
    let dir = NSString(string: "~/.config/psp-wallpaper").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/config.json"
}()

// --preview: draw above every window instead of on the desktop (demo / screensaver-ish)
let previewMode = CommandLine.arguments.contains("--preview")

struct Config: Codable {
    var colorTop: String?
    var colorBottom: String?
    var waveColor: String?
    var crestColor: String?
    var waveCount: Int?
    var waveOpacity: Float?
    var amplitude: Float?
    var speed: Float?
    var crestGlow: Float?
    var gradientAngle: Float?
    var fps: Int?
    var renderScale: Float?
}

// Mirrored byte-for-byte by struct U in the shader source below.
struct Uniforms {
    var resolution = SIMD2<Float>(0, 0)
    var time: Float = 0
    var waveCount: Float = 2
    var colorTop = SIMD4<Float>(0.24, 0.27, 0.34, 1)
    var colorBottom = SIMD4<Float>(0.66, 0.68, 0.87, 1)
    var waveColor = SIMD4<Float>(0.56, 0.66, 0.80, 1)
    var crestColor = SIMD4<Float>(1, 1, 1, 1)
    var waveOpacity: Float = 0.35
    var amplitude: Float = 0.12
    var speed: Float = 0.4
    var crestGlow: Float = 0.6
    var gradientAngle: Float = 45
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct U {
    float2 resolution;
    float  time;
    float  waveCount;
    float4 colorTop;
    float4 colorBottom;
    float4 waveColor;
    float4 crestColor;
    float  waveOpacity;
    float  amplitude;
    float  speed;
    float  crestGlow;
    float  gradientAngle;
    float  pad0; float pad1; float pad2;
};

vertex float4 vmain(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

fragment float4 fmain(float4 pos [[position]], constant U& u [[buffer(0)]]) {
    float2 uv = pos.xy / u.resolution;
    float a = u.gradientAngle * 0.01745329;
    float2 dir = float2(cos(a), sin(a));
    float g = clamp(dot(uv - 0.5, dir) * 1.2 + 0.5, 0.0, 1.0);
    float3 col = mix(u.colorTop.rgb, u.colorBottom.rgb, g);
    int n = clamp(int(u.waveCount), 1, 5);
    for (int i = 0; i < n; i++) {
        float fi = float(i);
        float ph = u.time * u.speed * (0.7 + 0.23 * fi) + fi * 2.4;
        float y = 0.52 + 0.09 * fi
                + u.amplitude * (0.6 * sin(uv.x * 2.3 + ph)
                               + 0.4 * sin(uv.x * 4.1 - ph * 1.31 + fi * 1.7));
        float below = smoothstep(y, y + 0.015, uv.y);
        float fade = clamp(exp(-(uv.y - y) * 3.5), 0.25, 1.0); // band brightest at crest, fades with depth
        col = mix(col, u.waveColor.rgb, below * u.waveOpacity * fade);
        float d = abs(uv.y - y);
        col += u.crestColor.rgb * u.crestGlow * (0.5 * exp(-d * 260.0) + 0.18 * exp(-d * 40.0));
    }
    // dither kills gradient banding at 1x render scale
    float dith = (fract(sin(dot(pos.xy, float2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    return float4(col + dith, 1.0);
}
"""

func hexColor(_ s: String?, _ fallback: SIMD4<Float>) -> SIMD4<Float> {
    guard var h = s?.trimmingCharacters(in: .whitespaces) else { return fallback }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return fallback }
    return SIMD4<Float>(Float((v >> 16) & 0xff) / 255,
                        Float((v >> 8) & 0xff) / 255,
                        Float(v & 0xff) / 255, 1)
}

func loadConfig() -> Config? {
    guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
}

func makeUniforms(_ c: Config) -> Uniforms {
    var u = Uniforms()
    u.colorTop = hexColor(c.colorTop, u.colorTop)
    u.colorBottom = hexColor(c.colorBottom, u.colorBottom)
    u.waveColor = hexColor(c.waveColor, u.waveColor)
    u.crestColor = hexColor(c.crestColor, u.crestColor)
    u.waveCount = Float(min(max(c.waveCount ?? 2, 1), 5))
    u.waveOpacity = c.waveOpacity ?? u.waveOpacity
    u.amplitude = c.amplitude ?? u.amplitude
    u.speed = c.speed ?? u.speed
    u.crestGlow = c.crestGlow ?? u.crestGlow
    u.gradientAngle = c.gradientAngle ?? u.gradientAngle
    return u
}

var gConfig = loadConfig() ?? Config()
var gBase = makeUniforms(gConfig)
let t0 = CACurrentMediaTime()

if CommandLine.arguments.contains("--selftest") {
    assert(hexColor("#ff8000", .zero) == SIMD4<Float>(1, Float(0x80) / 255, 0, 1))
    assert(hexString(Color(.sRGB, red: 1, green: 0.5, blue: 0)) == "#ff8000")
    assert(hexColor("bogus", SIMD4<Float>(9, 9, 9, 9)) == SIMD4<Float>(9, 9, 9, 9))
    let sample = "{\"colorTop\":\"#112233\",\"fps\":24}".data(using: .utf8)!
    let c = try! JSONDecoder().decode(Config.self, from: sample)
    assert(c.fps == 24 && c.colorTop == "#112233")
    assert(MemoryLayout<Uniforms>.stride == 112) // must match MSL struct U
    print("selftest OK")
    exit(0)
}

// MARK: - Settings UI (menu bar -> Settings window)

func hexString(_ c: Color) -> String {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
    return String(format: "#%02x%02x%02x",
                  Int(round(ns.redComponent * 255)),
                  Int(round(ns.greenComponent * 255)),
                  Int(round(ns.blueComponent * 255)))
}

final class Settings: ObservableObject {
    static let shared = Settings()
    @Published var colorTop: Color = .black
    @Published var colorBottom: Color = .black
    @Published var waveColor: Color = .black
    @Published var crestColor: Color = .white
    @Published var waveCount: Double = 2
    @Published var waveOpacity: Double = 0.35
    @Published var amplitude: Double = 0.12
    @Published var speed: Double = 0.4
    @Published var crestGlow: Double = 0.6
    @Published var gradientAngle: Double = 45
    @Published var fps: Double = 30
    @Published var renderScale: Double = 1
    private var sub: AnyCancellable?
    private var saveTimer: Timer?

    init() {
        seed(from: gConfig)
        sub = objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.apply() }
        }
    }

    private func seed(from cfg: Config) {
        let u = makeUniforms(cfg)
        func c(_ v: SIMD4<Float>) -> Color {
            Color(.sRGB, red: Double(v.x), green: Double(v.y), blue: Double(v.z))
        }
        colorTop = c(u.colorTop); colorBottom = c(u.colorBottom)
        waveColor = c(u.waveColor); crestColor = c(u.crestColor)
        waveCount = Double(u.waveCount); waveOpacity = Double(u.waveOpacity)
        amplitude = Double(u.amplitude); speed = Double(u.speed)
        crestGlow = Double(u.crestGlow); gradientAngle = Double(u.gradientAngle)
        fps = Double(cfg.fps ?? 30); renderScale = Double(cfg.renderScale ?? 1)
    }

    func reset() { seed(from: Config()) }

    func asConfig() -> Config {
        Config(colorTop: hexString(colorTop), colorBottom: hexString(colorBottom),
               waveColor: hexString(waveColor), crestColor: hexString(crestColor),
               waveCount: Int(waveCount), waveOpacity: Float(waveOpacity),
               amplitude: Float(amplitude), speed: Float(speed),
               crestGlow: Float(crestGlow), gradientAngle: Float(gradientAngle),
               fps: Int(fps), renderScale: Float(renderScale))
    }

    // Applies instantly while dragging; file save debounced 0.5s.
    // ponytail: hand-edits to config.json while this window is open won't move the sliders
    private func apply() {
        gConfig = asConfig()
        gBase = makeUniforms(gConfig)
        (NSApp.delegate as? AppDelegate)?.applyConfig()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Settings.shared.save()
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(asConfig()) {
            try? d.write(to: URL(fileURLWithPath: configPath))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var s = Settings.shared

    var body: some View {
        Form {
            Section("Colors") {
                ColorPicker("Top", selection: $s.colorTop, supportsOpacity: false)
                ColorPicker("Bottom", selection: $s.colorBottom, supportsOpacity: false)
                ColorPicker("Wave", selection: $s.waveColor, supportsOpacity: false)
                ColorPicker("Crest", selection: $s.crestColor, supportsOpacity: false)
            }
            Section("Wave") {
                row("Waves", $s.waveCount, 1...5, step: 1, fmt: "%.0f")
                row("Opacity", $s.waveOpacity, 0...1)
                row("Amplitude", $s.amplitude, 0...0.4)
                row("Speed", $s.speed, 0...2)
                row("Crest glow", $s.crestGlow, 0...2)
                row("Angle", $s.gradientAngle, 0...360, step: 5, fmt: "%.0f")
            }
            Section("Performance") {
                row("FPS", $s.fps, 10...60, step: 1, fmt: "%.0f")
                row("Render scale", $s.renderScale, 0.5...2, step: 0.25)
            }
            Button("Reset to PSP defaults") { s.reset() }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 560)
    }

    private func row(_ label: String, _ v: Binding<Double>, _ range: ClosedRange<Double>,
                     step: Double? = nil, fmt: String = "%.2f") -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .leading)
            if let step { Slider(value: v, in: range, step: step) }
            else { Slider(value: v, in: range) }
            Text(String(format: fmt, v.wrappedValue))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    let queue: MTLCommandQueue
    let pso: MTLRenderPipelineState
    init(device: MTLDevice, pso: MTLRenderPipelineState) {
        self.queue = device.makeCommandQueue()!
        self.pso = pso
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var u = gBase
        // ponytail: Float time wraps every 6h — one visible seam per quarter-day keeps sin() precise
        u.time = Float((CACurrentMediaTime() - t0).truncatingRemainder(dividingBy: 21600))
        u.resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        enc.setRenderPipelineState(pso)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var views: [MTKView] = []
    var renderers: [Renderer] = []
    var pollTimer: Timer?
    var lastMTime: Date?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var device: MTLDevice!
    var pso: MTLRenderPipelineState!
    var occlusionTokens: [NSObjectProtocol] = []
    var rebuildTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        device = MTLCopyAllDevices().first(where: { $0.isLowPower })
            ?? MTLCreateSystemDefaultDevice()!
        let lib = try! device.makeLibrary(source: shaderSource, options: nil)
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = lib.makeFunction(name: "vmain")
        pd.fragmentFunction = lib.makeFunction(name: "fmain")
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pso = try! device.makeRenderPipelineState(descriptor: pd)

        buildWindows()
        applyConfig()
        lastMTime = mtime()
        // ponytail: 1s mtime poll beats fs-event re-arm dances; one stat/sec is free
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkReload()
        }
        // display plugged/unplugged or resolution changed -> rebuild (debounced; fires in bursts)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.rebuildTimer?.invalidate()
            self.rebuildTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                (NSApp.delegate as? AppDelegate)?.rebuildWindows()
            }
        }
        setupMenuBar()
        if ProcessInfo.processInfo.environment["PSP_SETTINGS"] != nil { openSettings() }
        if ProcessInfo.processInfo.environment["PSP_TEST_REBUILD"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.rebuildWindows() }
        }
        NSLog("PSP wallpaper on %d screen(s). Menu bar wave icon for settings, quit from there.",
              windows.count)
    }

    func buildWindows() {
        NSScreen.screens.forEach(addWindow)
    }

    func addWindow(for screen: NSScreen) {
            let win = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
            win.level = previewMode ? .screenSaver
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.isOpaque = true
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.isReleasedWhenClosed = false
            win.backgroundColor = .black

            let view = MTKView(frame: win.contentLayoutRect, device: device)
            view.autoResizeDrawable = false
            view.autoresizingMask = [.width, .height]
            view.colorPixelFormat = .bgra8Unorm
            let r = Renderer(device: device, pso: pso)
            view.delegate = r
            win.contentView = view
            win.orderFrontRegardless()

            let tok = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: win, queue: .main
            ) { [weak view] note in
                guard let v = view, let w = note.object as? NSWindow else { return }
                let visible = w.occlusionState.contains(.visible)
                if v.isPaused == visible { NSLog("wallpaper %@", visible ? "resumed" : "paused") }
                v.isPaused = !visible
            }
            occlusionTokens.append(tok)

            windows.append(win)
            views.append(view)
            renderers.append(r)
    }

    // Diff instead of tear-down-everything: untouched screens keep their window
    // (no black flash), and spurious notifications with an unchanged layout are ignored.
    func rebuildWindows() {
        let wanted = Set(NSScreen.screens.map { NSStringFromRect($0.frame) })
        let current = Set(windows.map { NSStringFromRect($0.frame) })
        guard wanted != current else { return }
        for i in windows.indices.reversed()
        where !wanted.contains(NSStringFromRect(windows[i].frame)) {
            NotificationCenter.default.removeObserver(occlusionTokens[i])
            occlusionTokens.remove(at: i)
            windows[i].close()
            windows.remove(at: i)
            views.remove(at: i)
            renderers.remove(at: i)
        }
        let have = Set(windows.map { NSStringFromRect($0.frame) })
        for screen in NSScreen.screens where !have.contains(NSStringFromRect(screen.frame)) {
            addWindow(for: screen)
        }
        applyConfig()
        NSLog("screens changed — now %d screen(s)", windows.count)
    }

    func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "water.waves",
                                     accessibilityDescription: "PSP Wave")
        let menu = NSMenu()
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        s.target = self
        menu.addItem(s)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PSP Wave",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "PSP Wave"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            // drop the window on close so the SwiftUI hierarchy deallocates (~40MB)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in self?.settingsWindow = nil }
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func mtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: configPath))?[.modificationDate] as? Date
    }

    func checkReload() {
        let m = mtime()
        guard m != lastMTime else { return }
        lastMTime = m
        guard let c = loadConfig() else {
            NSLog("config.json unreadable — keeping last good config")
            return
        }
        gConfig = c
        gBase = makeUniforms(c)
        applyConfig()
        NSLog("config reloaded")
    }

    func applyConfig() {
        let fps = min(max(gConfig.fps ?? 30, 1), 120)
        let scale = CGFloat(min(max(gConfig.renderScale ?? 1.0, 0.25), 3.0))
        for (i, v) in views.enumerated() {
            v.preferredFramesPerSecond = fps
            let f = windows[i].frame.size
            v.drawableSize = CGSize(width: f.width * scale, height: f.height * scale)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
