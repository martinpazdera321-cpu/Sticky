#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Cat walker (window that moves along the bottom of the screen)
final class CatWalker {
    static let shared = CatWalker()
    private var window: NSWindow?
    private var timer: Timer?
    private var keepWalking = false
    private var lastTick = Date()
    private let width: CGFloat = 50
    private let height: CGFloat = 38
    private let speed: CGFloat = 90        // pixels per second (bigger = faster)

    /// One walk across the screen
    func walk() {
        keepWalking = false
        begin()
    }

    /// Keeps walking (for scanning) until stopScanning() is called
    func startScanning() {
        keepWalking = true
        begin()
    }

    /// Cat finishes its current walk and leaves
    func stopScanning() {
        keepWalking = false
    }

    private func begin() {
        guard window == nil, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame

        let w = NSWindow(contentRect: NSRect(x: f.minX - width, y: f.minY + 2, width: width, height: height),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .screenSaver               // on top of everything
        w.ignoresMouseEvents = true          // clicks go through the cat
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: CatView())
        w.orderFrontRegardless()
        window = w
        lastTick = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self, let w = self.window, let screen = NSScreen.main else { return }
            let now = Date()
            let dt = now.timeIntervalSince(self.lastTick)
            self.lastTick = now
            let f = screen.visibleFrame
            var x = w.frame.origin.x + self.speed * dt

            if x > f.maxX {                  // reached the right edge
                if self.keepWalking {
                    x = f.minX - self.width  // start again from the left
                } else {
                    t.invalidate()
                    w.orderOut(nil)
                    self.window = nil
                    return
                }
            }
            w.setFrameOrigin(NSPoint(x: x, y: f.minY + 2))
        }
    }
}

// MARK: - The cat (drawn in code, legs + tail animated)
struct CatView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let swing = sin(t * 10) * 25           // legs swinging
            let bob = abs(sin(t * 10)) * 1.2       // body bouncing
            let tail = sin(t * 3) * 20             // tail wagging

            ZStack {
                // tail
                Capsule().frame(width: 3, height: 16)
                    .rotationEffect(.degrees(-35 + tail), anchor: .bottom)
                    .position(x: 7, y: 12 - bob)
                // back legs
                leg(-swing).position(x: 13, y: 26)
                leg(swing).position(x: 17, y: 26)
                // front legs
                leg(swing).position(x: 29, y: 26)
                leg(-swing).position(x: 33, y: 26)
                // body
                Capsule().frame(width: 28, height: 12)
                    .position(x: 22, y: 19 - bob)
                // head + ears
                Circle().frame(width: 13, height: 13)
                    .position(x: 37, y: 13 - bob)
                Triangle().frame(width: 5, height: 6)
                    .position(x: 33.5, y: 6.5 - bob)
                Triangle().frame(width: 5, height: 6)
                    .position(x: 40, y: 6.5 - bob)
                // eye
                Circle().fill(Color.yellow).frame(width: 2.5, height: 2.5)
                    .position(x: 40, y: 12 - bob)
            }
            .foregroundStyle(.black)
            .frame(width: 46, height: 34)
            .shadow(color: .white.opacity(0.8), radius: 1)   // visible on dark backgrounds
        }
    }

    private func leg(_ angle: Double) -> some View {
        Capsule().frame(width: 3, height: 10)
            .rotationEffect(.degrees(angle), anchor: .top)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
