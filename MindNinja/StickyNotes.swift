#if os(macOS)
import SwiftUI
import AppKit
import Combine
import QuartzCore

// Window that can be typed in even without a title bar
final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowRef {
    weak var window: NSWindow?
}

struct StickyColor {
    let name: String
    let paper: Color
    let strip: Color
}

// One sticky note (text + color)
final class StickyModel: ObservableObject {
    let id: UUID
    let color: Int
    @Published var text: String

    init(id: UUID = UUID(), text: String = "", color: Int) {
        self.id = id
        self.text = text
        self.color = color
    }
}

// What gets saved to disk
nonisolated struct StickySaved: Codable {
    var id: UUID
    var text: String
    var x: Double
    var y: Double
    var color: Int
}

final class BinState: ObservableObject {
    @Published var hot = false
}

// MARK: - Manager
final class StickyNotes {
    static let shared = StickyNotes()

    static let palette: [StickyColor] = [
        StickyColor(name: "Yellow", paper: Color(red: 1.00, green: 0.93, blue: 0.50), strip: Color(red: 0.98, green: 0.85, blue: 0.32)),
        StickyColor(name: "Pink",   paper: Color(red: 1.00, green: 0.78, blue: 0.85), strip: Color(red: 0.97, green: 0.64, blue: 0.75)),
        StickyColor(name: "Blue",   paper: Color(red: 0.72, green: 0.87, blue: 1.00), strip: Color(red: 0.56, green: 0.76, blue: 0.98)),
        StickyColor(name: "Green",  paper: Color(red: 0.76, green: 0.94, blue: 0.68), strip: Color(red: 0.60, green: 0.86, blue: 0.53)),
    ]

    private var notes: [UUID: (window: NSWindow, model: StickyModel)] = [:]
    private let saveKey = "stickyNotes"
    private let size = NSSize(width: 270, height: 270)

    // The bin in the bottom right corner
    private var binWindow: NSWindow?
    private var binVisible = false
    private let bin = BinState()

    // New empty note in the middle of the screen
    func new() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let offset = CGFloat(notes.count % 6) * 26
        let origin = NSPoint(x: f.midX - size.width / 2 + offset,
                             y: f.midY - size.height / 2 - offset)
        let c = UserDefaults.standard.integer(forKey: "stickyColor")
        let model = StickyModel(color: min(max(c, 0), Self.palette.count - 1))
        show(model, at: origin, focus: true)
        save()
    }

    // Brings back all notes from last time (called when the app starts)
    func restore() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([StickySaved].self, from: data) else { return }
        for s in saved {
            let model = StickyModel(id: s.id, text: s.text, color: s.color)
            show(model, at: NSPoint(x: s.x, y: s.y), focus: false)
        }
    }

    func save() {
        let list = notes.values.map {
            StickySaved(id: $0.model.id, text: $0.model.text,
                        x: $0.window.frame.origin.x, y: $0.window.frame.origin.y,
                        color: $0.model.color)
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func show(_ model: StickyModel, at origin: NSPoint, focus: Bool) {
        let p = StickyPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating                                     // stays on top
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]  // every desktop, also full screen
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false                             // DON'T hide when you click another app
        p.isFloatingPanel = true
        p.canHide = false                                       // "Hide others" (⌥⌘H) can't hide it either

        let ref = WindowRef()
        ref.window = p
        p.contentView = NSHostingView(rootView: StickyNoteView(ref: ref, model: model))
        notes[model.id] = (p, model)

        if focus {
            NSApp.activate(ignoringOtherApps: true)
            p.makeKeyAndOrderFront(nil)
        } else {
            p.orderFrontRegardless()
        }
    }

    // MARK: Bin
    private var binRect: NSRect {
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: f.maxX - 96, y: f.minY + 24, width: 72, height: 72)
    }

    private func showBin() {
        if binWindow == nil {
            let w = NSWindow(contentRect: binRect, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: BinView(state: bin))
            binWindow = w
        }
        binVisible = true
        binWindow?.setFrame(binRect, display: true)
        binWindow?.alphaValue = 0
        binWindow?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            binWindow?.animator().alphaValue = 1
        }
    }

    private func hideBin() {
        binVisible = false
        bin.hot = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.binWindow?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.binVisible == false { self?.binWindow?.orderOut(nil) }
        })
    }

    private func isOverBin(_ mouse: NSPoint) -> Bool {
        binRect.insetBy(dx: -24, dy: -24).contains(mouse)
    }

    // While a note is dragged: show the bin, light it up when you're over it
    func dragChanged(mouse: NSPoint) {
        if !binVisible { showBin() }
        let hot = isOverBin(mouse)
        if bin.hot != hot {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { bin.hot = hot }
        }
    }

    /// Returns true if the note was dropped on the bin
    func dragEnded(mouse: NSPoint) -> Bool {
        if isOverBin(mouse) { return true }
        hideBin()
        save()
        return false
    }

    // Crumpled note flies into the bin and is gone for good
    func throwAway(_ id: UUID) {
        guard let entry = notes[id] else { return }
        let w = entry.window
        notes[id] = nil
        save()
        if !binVisible { showBin() }

        let target = binRect
        var dest = w.frame
        dest.origin = NSPoint(x: target.midX - dest.width / 2, y: target.midY - dest.height / 2)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().setFrame(dest, display: true)
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.close()
            PaperSound.play("toss")
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { self?.bin.hot = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.hideBin() }
        })
    }
}

// MARK: - The bin
struct BinView: View {
    @ObservedObject var state: BinState

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.8))
            Image(systemName: state.hot ? "trash.fill" : "trash")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(state.hot ? Color.red : Color.white)
        }
        .frame(width: 60, height: 60)
        .scaleEffect(state.hot ? 1.15 : 1)
        .frame(width: 72, height: 72)
    }
}

// MARK: - Paper sounds (Sounds/crumple.wav, Sounds/toss.wav)
enum PaperSound {
    private static var playing: [NSSound] = []
    static func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        playing.append(sound)
        if playing.count > 6 { playing.removeFirst() }
        sound.play()
    }
}

// MARK: - Crease lines drawn on the paper while it crumples
struct Creases: View {
    private let lines: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.10, 0.20, 0.62, 0.48), (0.30, 0.92, 0.80, 0.30), (0.00, 0.60, 0.50, 0.78),
        (0.55, 0.05, 0.92, 0.70), (0.20, 0.42, 0.46, 0.08), (0.60, 0.98, 1.00, 0.55),
        (0.05, 0.95, 0.36, 0.55), (0.40, 0.55, 0.98, 0.20), (0.00, 0.30, 0.30, 0.00),
    ]
    var body: some View {
        Canvas { ctx, size in
            for l in lines {
                var dark = Path()
                dark.move(to: CGPoint(x: l.0 * size.width, y: l.1 * size.height))
                dark.addLine(to: CGPoint(x: l.2 * size.width, y: l.3 * size.height))
                ctx.stroke(dark, with: .color(.black.opacity(0.22)), lineWidth: 1.4)
                ctx.stroke(dark.offsetBy(dx: 1.5, dy: 1.5), with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
        }
    }
}

// MARK: - The sticky note
struct StickyNoteView: View {
    let ref: WindowRef
    @ObservedObject var model: StickyModel

    // 0 = normal, 1 = wrinkling, 2 = folding, 3 = paper ball
    @State private var stage = 0
    @State private var startOrigin: NSPoint?
    @State private var startMouse: NSPoint?
    @FocusState private var focused: Bool

    private var c: StickyColor {
        StickyNotes.palette[min(max(model.color, 0), StickyNotes.palette.count - 1)]
    }

    private var scaleX: CGFloat  { [1, 0.88, 0.52, 0.19][stage] }
    private var scaleY: CGFloat  { [1, 0.78, 0.48, 0.19][stage] }
    private var angle: Double    { [-1.5, -9, 28, 320][stage] }
    private var corner: CGFloat  { [3, 22, 70, 135][stage] }
    private var textOpacity: Double   { [1.0, 0.45, 0.0, 0.0][stage] }
    private var creaseOpacity: Double { [0.0, 0.6, 0.9, 1.0][stage] }

    var body: some View {
        VStack(spacing: 0) {
            // Top strip: drag here to move (drop on the bin to throw away)
            HStack {
                Text("📝").font(.caption)
                Spacer()
                Button { crumple() } label: {
                    Text("🗑️ Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("I don't need it")
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(c.strip)
            .contentShape(Rectangle())
            .gesture(moveGesture)

            // Writing area
            TextEditor(text: $model.text)
                .font(.custom("Noteworthy", size: 16))
                .foregroundStyle(.black.opacity(0.85))
                .scrollContentBackground(.hidden)
                .padding(10)
                .focused($focused)
                .opacity(textOpacity)
                .onChange(of: model.text) { _, _ in StickyNotes.shared.save() }
        }
        .background(
            LinearGradient(colors: [c.paper, c.strip.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(Creases().opacity(creaseOpacity))                 // wrinkles appear
        .overlay(                                                             // ball shading
            Rectangle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.35)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 160))
                .opacity(stage == 3 ? 1.0 : 0.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 2, y: 4)
        .scaleEffect(x: scaleX, y: scaleY)
        .rotationEffect(.degrees(angle))
        .padding(14)
        .onAppear { if model.text.isEmpty { focused = true } }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard let w = ref.window else { return }
                let mouse = NSEvent.mouseLocation
                if startOrigin == nil {
                    startOrigin = w.frame.origin
                    startMouse = mouse
                }
                if let o = startOrigin, let m = startMouse {
                    w.setFrameOrigin(NSPoint(x: o.x + mouse.x - m.x, y: o.y + mouse.y - m.y))
                }
                StickyNotes.shared.dragChanged(mouse: mouse)
            }
            .onEnded { _ in
                startOrigin = nil
                startMouse = nil
                if StickyNotes.shared.dragEnded(mouse: NSEvent.mouseLocation) { crumple() }
            }
    }

    // Paper crumples in 3 steps, then flies into the bin
    private func crumple() {
        guard stage == 0 else { return }
        PaperSound.play("crumple")
        withAnimation(.easeIn(duration: 0.14)) { stage = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeInOut(duration: 0.18)) { stage = 2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { stage = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            StickyNotes.shared.throwAway(model.id)
        }
    }
}
#endif
