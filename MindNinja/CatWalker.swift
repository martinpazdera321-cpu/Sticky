#if os(macOS)
import SwiftUI
import AppKit

final class CatWalker {
    static let shared = CatWalker()
    private var window: NSWindow?
    private var timer: Timer?

    func walk() {
        guard window == nil, let screen = NSScreen.main else { return }
        let size: CGFloat = 70
        let frame = screen.visibleFrame
        let startX = frame.maxX             // starts at the right edge
        let endX = frame.minX - size        // walks out on the left
        let y = frame.minY + 4              // just above the Dock

        let w = NSWindow(contentRect: NSRect(x: startX, y: y, width: size, height: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .screenSaver              // on top of everything
        w.ignoresMouseEvents = true         // clicks go through the cat
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: CatView())
        w.orderFrontRegardless()
        window = w

        let duration: Double = 12           // seconds to cross the screen
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            let p = min(Date().timeIntervalSince(start) / duration, 1)
            w.setFrameOrigin(NSPoint(x: startX + (endX - startX) * p, y: y))
            if p >= 1 {
                t.invalidate()
                w.orderOut(nil)
                self?.window = nil
            }
        }
    }
}

struct CatView: View {
    @State private var step = false
    let flip = false   // change to true if the cat walks backwards

    var body: some View {
        Image(systemName: "cat.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.black)
            .shadow(color: .white.opacity(0.7), radius: 1.5)   // visible on dark backgrounds
            .scaleEffect(x: flip ? -1 : 1, y: 1)
            .offset(y: step ? -4 : 0)                         // bobbing walk
            .rotationEffect(.degrees(step ? -3 : 3), anchor: .bottom)
            .animation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true), value: step)
            .onAppear { step = true }
    }
}
#endif

