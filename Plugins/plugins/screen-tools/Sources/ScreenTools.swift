import Cocoa
import MouseGestures

@objc(ScreenToolsPlugin)
public final class ScreenToolsPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.screentools" }
    public var name: String { "Screen Tools" }
    public override var description: String { "Colour picker, pointer finder, screen text and QR reader" }
    public var version: String { "1.2.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .system }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil) }

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "colorFormat", title: "Colour format", kind: .choice([
            PluginSettingChoice("hex", "Hex  #RRGGBB"), PluginSettingChoice("rgb", "RGB  rgb(r, g, b)"), PluginSettingChoice("hsl", "HSL  hsl(h, s%, l%)")]),
                           defaultValue: AnyCodable("hex"), help: "How a picked colour is copied."),
        PluginSettingField(key: "info", title: "Permissions", kind: .info,
                           help: "Copy Text from Screen and Scan QR Code use macOS's screenshot selector, so MouseGestures needs Screen Recording permission (System Settings ▸ Privacy & Security). Nothing is saved or sent anywhere."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "pick_color", name: "Pick Color from Screen", description: "Click anywhere to copy that pixel's colour", icon: "eyedropper"),
        PluginAction(id: "find_cursor", name: "Find Pointer", description: "Flash a ring around the pointer", icon: "scope"),
        PluginAction(id: "read_text", name: "Copy Text from Screen", description: "Drag a box around text anywhere (even in images or videos) and copy it", icon: "text.viewfinder"),
        PluginAction(id: "scan_code", name: "Scan QR Code", description: "Drag a box around a QR code or barcode and copy what it says", icon: "qrcode.viewfinder"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    private static var sampler: NSColorSampler?

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "pick_color":
            let format = settings?.string("colorFormat", default: "hex") ?? "hex"
            DispatchQueue.main.async {
                let s = NSColorSampler()
                Self.sampler = s
                s.show { color in
                    Self.sampler = nil
                    guard let color = color else { return }
                    let text = Self.format(color, as: format)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    context.showNotification(title: "Colour copied", message: text, style: .success)
                }
            }
        case "read_text": Self.captureRegion(context) { image in
            let text = ScreenReader.text(in: image)
            guard !text.isEmpty else { context.showNotification(title: "Copy Text from Screen", message: "No text found. If the area clearly has text, allow Screen Recording for MouseGestures in System Settings ▸ Privacy & Security.", style: .warning); return }
            Self.copy(text)
            context.showNotification(title: "Text copied", message: String(text.prefix(100)), style: .success)
        }
        case "scan_code": Self.captureRegion(context) { image in
            let codes = ScreenReader.codes(in: image)
            guard !codes.isEmpty else { context.showNotification(title: "Scan QR Code", message: "No code found in that area", style: .warning); return }
            Self.copy(codes.joined(separator: "\n"))
            context.showNotification(title: "Code copied", message: String(codes[0].prefix(100)), style: .success)
        }
        case "find_cursor":
            DispatchQueue.main.async { Self.flashRing(at: NSEvent.mouseLocation) }
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    /// Lets the user drag a region (macOS's own screenshot selector), then hands the image over. Runs in the
    /// background so the gesture returns at once; Esc cancels. Needs Screen Recording permission.
    private static func captureRegion(_ context: PluginContext, _ handler: @escaping (CGImage) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("mg-capture-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", file.path]
            do { try p.run() } catch { return }
            p.waitUntilExit()
            guard let image = ScreenReader.load(file) else { return }     // cancelled: no file
            handler(image)
        }
    }

    private static func copy(_ text: String) {
        DispatchQueue.main.async { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    }

    static func format(_ color: NSColor, as kind: String) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        switch kind {
        case "rgb": return "rgb(\(r), \(g), \(b))"
        case "hsl":
            return "hsl(\(Int((c.hueComponent * 360).rounded()) % 360), \(Int((hslSaturation(c) * 100).rounded()))%, \(Int((hslLightness(c) * 100).rounded()))%)"
        default: return String(format: "#%02X%02X%02X", r, g, b)
        }
    }

    private static func hslLightness(_ c: NSColor) -> CGFloat { (max(c.redComponent, c.greenComponent, c.blueComponent) + min(c.redComponent, c.greenComponent, c.blueComponent)) / 2 }
    private static func hslSaturation(_ c: NSColor) -> CGFloat {
        let mx = max(c.redComponent, c.greenComponent, c.blueComponent), mn = min(c.redComponent, c.greenComponent, c.blueComponent)
        guard mx != mn else { return 0 }
        let l = (mx + mn) / 2
        return (mx - mn) / (1 - abs(2 * l - 1))
    }

    private static var ringWindows: [NSWindow] = []

    private static func flashRing(at p: NSPoint) {
        let size: CGFloat = 220
        let w = NSWindow(contentRect: NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .screenSaver; w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(origin: .zero, size: NSSize(width: size, height: size)))
        v.wantsLayer = true
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: v.bounds.insetBy(dx: 8, dy: 8), transform: nil)
        ring.fillColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        ring.strokeColor = NSColor.systemRed.cgColor
        ring.lineWidth = 6
        ring.frame = v.bounds
        v.layer?.addSublayer(ring)
        w.contentView = v
        w.orderFrontRegardless()
        ringWindows.append(w)

        let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 1.0; scale.toValue = 0.3
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1.0; fade.toValue = 0.0
        let group = CAAnimationGroup(); group.animations = [scale, fade]; group.duration = 1.0
        group.timingFunction = CAMediaTimingFunction(name: .easeOut); group.isRemovedOnCompletion = false; group.fillMode = .forwards
        ring.add(group, forKey: "find")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            w.orderOut(nil)
            ringWindows.removeAll { $0 === w }
        }
    }
}
