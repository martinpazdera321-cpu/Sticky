#if os(macOS)
import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - App delegate: 🧠 icon in the menu bar opens the notch
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Sticky")
        item.button?.target = self
        item.button?.action = #selector(toggleNotch)
        statusItem = item

        StickyNotes.shared.restore()          // bring back sticky notes from last time
    }

    @objc func toggleNotch() {
        NotchController.shared.toggle()
    }
}

// MARK: - Notch state
enum NotchMode { case closed, buttons, settings }

final class NotchState: ObservableObject {
    @Published var mode: NotchMode = .closed
    @Published var notchHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 200

    // Size of the black shape for each mode
    var shapeSize: CGSize {
        switch mode {
        case .closed:   return CGSize(width: notchWidth, height: notchHeight)
        case .buttons:  return CGSize(width: max(notchWidth + 70, 270), height: notchHeight + 76)
        case .settings: return CGSize(width: max(notchWidth + 110, 370), height: notchHeight + 330)
        }
    }
    var topRadius: CGFloat { mode == .closed ? 6 : 10 }
    var bottomRadius: CGFloat {
        switch mode {
        case .closed: return 10
        case .buttons: return 24
        case .settings: return 30
        }
    }
}

// MARK: - Notch controller
// The window never moves or resizes (that caused the freeze).
// Only the black shape inside it grows and shrinks.
final class NotchController {
    static let shared = NotchController()
    let state = NotchState()
    private var panel: NSPanel?
    private var clickMonitor: Any?

    func toggle() {
        state.mode == .closed ? open() : close()
    }

    func open() {
        guard let screen = NSScreen.main else { return }
        measureNotch(screen)
        let p = panel ?? makePanel()
        panel = p

        // fixed window at the top center, big enough for the largest mode
        let w: CGFloat = max(state.notchWidth + 110, 370) + 40
        let h: CGFloat = state.notchHeight + 330 + 30
        let f = screen.frame
        p.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), display: false)
        p.orderFrontRegardless()

        DispatchQueue.main.async { self.setMode(.buttons) }

        // click anywhere else = close
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }
    }

    func close() {
        guard state.mode != .closed else { return }
        setMode(.closed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            if self?.state.mode == .closed { self?.panel?.orderOut(nil) }
        }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    func setMode(_ mode: NotchMode) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { state.mode = mode }
    }

    private func measureNotch(_ screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            state.notchHeight = top
            state.notchWidth = screen.frame.width - l.width - r.width
        } else {                                   // Mac without a notch
            state.notchHeight = NSStatusBar.system.thickness
            state.notchWidth = 180
        }
    }

    private func makePanel() -> NSPanel {
        let p = StickyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // above the menu bar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        let host = NSHostingView(rootView: NotchView(state: state))
        host.sizingOptions = []
        p.contentView = host
        return p
    }
}

// MARK: - Notch shape: flows out of the screen edge like the real notch
// (idea from the open-source DynamicNotchKit / boring.notch projects)
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius, y: r.minY + topRadius),
                       control: CGPoint(x: r.minX + topRadius, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + topRadius, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius + bottomRadius, y: r.maxY),
                       control: CGPoint(x: r.minX + topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - topRadius, y: r.maxY - bottomRadius),
                       control: CGPoint(x: r.maxX - topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius, y: r.minY + topRadius))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.maxX - topRadius, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - What's inside the notch
struct NotchView: View {
    @ObservedObject var state: NotchState
    @AppStorage("autoScan") private var autoScan = true
    @AppStorage("shieldOn") private var shieldOn = true

    var body: some View {
        let size = state.shapeSize
        let shape = NotchShape(topRadius: state.topRadius, bottomRadius: state.bottomRadius)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)

                VStack(spacing: 0) {
                    Color.clear.frame(height: state.notchHeight)     // space behind the notch
                    switch state.mode {
                    case .closed:
                        EmptyView()
                    case .buttons:
                        buttons.transition(.opacity)
                    case .settings:
                        SettingsPanel().transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    if state.mode != .closed { pullHandle }
                }
                .padding(.horizontal, state.topRadius)
                .opacity(state.mode == .closed ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .shadow(color: .black.opacity(state.mode == .closed ? 0 : 0.35), radius: 10, y: 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            NotchButton(icon: "note.text", color: Color(red: 0.98, green: 0.80, blue: 0.20)) {
                NotchController.shared.close()
                StickyNotes.shared.new()
            }
            .help("New sticky note")

            NotchButton(icon: autoScan ? "checkmark.shield.fill" : "shield.slash",
                        color: autoScan ? .green : .gray) {
                autoScan.toggle()
                shieldOn = true
                DownloadWatcher.shared.startIfEnabled()
            }
            .help(autoScan ? "Auto-scan is ON" : "Auto-scan is OFF")

            NotchButton(icon: "brain.head.profile", color: .white) {
                NotchController.shared.setMode(.settings)
            }
            .help("Settings")
        }
        .padding(.top, 8)
    }

    // Little bar at the bottom: click it or push it up to hide the notch again
    private var pullHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { NotchController.shared.close() }
            .gesture(
                DragGesture(minimumDistance: 4).onEnded { v in
                    if v.translation.height < -6 { NotchController.shared.close() }
                }
            )
            .help("Push up to hide")
    }
}

// MARK: - Settings (opens inside the same notch, just bigger)
struct SettingsPanel: View {
    @AppStorage("stickyColor") private var stickyColor = 0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Button { NotchController.shared.setMode(.buttons) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "brain.head.profile")
                Text("Sticky").font(.headline)
                Spacer()
                Color.clear.frame(width: 13, height: 1)
            }

            // About
            Text("Sticky is your little paper helper. Catch quick ideas on sticky notes that stay on your screen, and let the Shield check every new download for danger.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Sticky note color
            VStack(alignment: .leading, spacing: 8) {
                Text("Sticky note color").font(.subheadline.weight(.semibold))
                HStack(spacing: 14) {
                    ForEach(0..<StickyNotes.palette.count, id: \.self) { i in
                        Circle()
                            .fill(StickyNotes.palette[i].paper)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: stickyColor == i ? 2 : 0)
                                    .padding(-4)
                            )
                            .contentShape(Circle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { stickyColor = i } }
                            .help(StickyNotes.palette[i].name)
                    }
                }
                .padding(.leading, 4)
            }

            // Open at login (so your sticky notes are always back)
            Toggle("Open Sticky at login", isOn: $openAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.subheadline)
                .onChange(of: openAtLogin) { _, on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }

            Spacer(minLength: 0)

            // Footer
            HStack {
                Text("Version \(version)")
                Spacer()
                Text("© 2026 Martin Pazdera")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

// MARK: - Round button inside the notch
struct NotchButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button {
            // tactile feedback: soft click sound + trackpad haptic
            PaperSound.play("tap")
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(hover ? 0.18 : 0.08)))
                .scaleEffect(hover ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
#endif
