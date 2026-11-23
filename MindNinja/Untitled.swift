#if os(macOS)
import SwiftUI
import AppKit
import QuartzCore

// Window that can be typed in even without a title bar
final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowRef {
    weak var window: NSWindow?
}

// MARK: - Manager: opens and throws away notes
final class StickyNotes {
    static let shared = StickyNotes()
    private var windows: [NSWindow] = []

    func new() {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 270, height: 270)
        let f = screen.visibleFrame
        let offset = CGFloat(windows.count % 6) * 26          // each new note a bit lower/right
        let origin = NSPoint(x: f.midX - size.width / 2 + offset,
                             y: f.midY - size.height / 2 - offset)

        let p = StickyPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating                                     // stays on top
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false

        let ref = WindowRef()
        ref.window = p
        p.contentView = NSHostingView(rootView: StickyNoteView(ref: ref) { [weak self, weak p] in
            if let p { self?.throwAway(p) }
        })

        windows.append(p)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    /// Flies the crumpled note to the bin (bottom right corner)
    func throwAway(_ w: NSWindow) {
        guard let screen = w.screen ?? NSScreen.main else { return }
        let f = screen.frame
        var target = w.frame
        target.origin = NSPoint(x: f.maxX - target.width / 2 - 60,
                                y: f.minY - target.height / 2 + 20)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().setFrame(target, display: true)
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.close()
            NSSound(named: "Bottle")?.play()
            self?.windows.removeAll { $0 === w }
        })
    }
}

// MARK: - The sticky note
struct StickyNoteView: View {
    let ref: WindowRef
    var onTrash: () -> Void

    @State private var text = ""
    @State private var crumpled = false
    @State private var startOrigin: NSPoint?
    @State private var startMouse: NSPoint?
    @FocusState private var focused: Bool

    private let paper = Color(red: 1.0, green: 0.93, blue: 0.50)
    private let paperDark = Color(red: 0.98, green: 0.85, blue: 0.32)

    var body: some View {
        VStack(spacing: 0) {
            // Top strip: drag here to move, 🗑️ to throw away
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
            .background(paperDark)
            .contentShape(Rectangle())
            .gesture(moveGesture)

            // Writing area
            TextEditor(text: $text)
                .font(.custom("Noteworthy", size: 16))
                .foregroundStyle(.black.opacity(0.85))
                .scrollContentBackground(.hidden)
                .padding(10)
                .focused($focused)
                .opacity(crumpled ? 0 : 1)
        }
        .background(
            LinearGradient(colors: [paper, paperDark.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: crumpled ? 130 : 3))     // becomes a ball
        .shadow(color: .black.opacity(0.25), radius: 6, x: 2, y: 4)
        .scaleEffect(crumpled ? 0.18 : 1)
        .rotationEffect(.degrees(crumpled ? 540 : -1.5))                    // slight tilt, then spin
        .padding(14)
        .onAppear { focused = true }
    }

    // Drag the top strip to move the note
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
            }
            .onEnded { _ in
                startOrigin = nil
                startMouse = nil
            }
    }

    private func crumple() {
        NSSound(named: "Tink")?.play()
        withAnimation(.easeIn(duration: 0.45)) { crumpled = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onTrash() }
    }
}
#endif
