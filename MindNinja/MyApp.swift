import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

// MARK: - Data
@Model
final class Note {
    var text: String
    var createdAt: Date
    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Translations
enum Strings {
    static let all: [String: [String: String]] = [
        "title":       ["en": "What's on your mind?", "cs": "Co máš na mysli?", "de": "Was geht dir durch den Kopf?"],
        "placeholder": ["en": "Type an idea and press Enter…", "cs": "Napiš nápad a stiskni Enter…", "de": "Idee eingeben und Enter drücken…"],
        "newNote":     ["en": "New note now", "cs": "Nová poznámka", "de": "Neue Notiz"],
        "noNotes":     ["en": "No notes yet", "cs": "Zatím žádné poznámky", "de": "Noch keine Notizen"],
        "quit":        ["en": "Quit MindNinja", "cs": "Ukončit MindNinja", "de": "MindNinja beenden"],
        "settings":    ["en": "Settings", "cs": "Nastavení", "de": "Einstellungen"],
        "theme":       ["en": "Theme", "cs": "Motiv", "de": "Design"],
        "language":    ["en": "Language", "cs": "Jazyk", "de": "Sprache"],
        "system":      ["en": "System", "cs": "Systém", "de": "System"],
        "light":       ["en": "Light", "cs": "Světlý", "de": "Hell"],
        "dark":        ["en": "Dark", "cs": "Tmavý", "de": "Dunkel"],
        "popupEvery":  ["en": "Pop-up every", "cs": "Zobrazit každých", "de": "Pop-up alle"],
        "min":         ["en": "min", "cs": "min", "de": "Min."],
        "save":        ["en": "Save", "cs": "Uložit", "de": "Speichern"],
        "saved":       ["en": "Saved ✓", "cs": "Uloženo ✓", "de": "Gespeichert ✓"],
        "next":        ["en": "Next pop-up at", "cs": "Další pop-up v", "de": "Nächstes Pop-up um"],
    ]
}

func tr(_ key: String, _ lang: String) -> String {
    Strings.all[key]?[lang] ?? Strings.all[key]?["en"] ?? key
}

let themes = ["system", "light", "dark"]

// MARK: - App
@main
struct MindNinjaApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Note.self)
        #if os(macOS)
        PopupController.shared.start(container: container)
        DownloadWatcher.shared.startIfEnabled()
        #endif
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Settings { EmptyView() }      // the 🧠 icon + notch are made in AppDelegate (MainMenu.swift)
        #else
        WindowGroup { Text("MindNinja for iPhone – coming soon") }
        #endif
    }
}

#if os(macOS)
// MARK: - Theme
func applyTheme(_ theme: String) {
    switch theme {
    case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
    case "dark":  NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    default:      NSApplication.shared.appearance = nil
    }
}

// MARK: - Pop-up controller
final class PopupController {
    static let shared = PopupController()
    private var container: ModelContainer!
    private var panel: NSPanel?
    private var timer: Timer?

    // Reads the minutes saved in Settings (default 120 = 2 hours)
    private var intervalSeconds: Double {
        let m = UserDefaults.standard.integer(forKey: "intervalMinutes")
        return Double(m > 0 ? m : 120) * 60
    }

    func start(container: ModelContainer) {
        self.container = container
        applyTheme(UserDefaults.standard.string(forKey: "theme") ?? "system")
        reschedule()
    }

    func reschedule() {
        timer?.invalidate()
        let secs = intervalSeconds
        UserDefaults.standard.set(Date().addingTimeInterval(secs).timeIntervalSince1970, forKey: "nextPopup")
        timer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            self?.show()
            self?.reschedule()
        }
    }

    func show() {
        applyTheme(UserDefaults.standard.string(forKey: "theme") ?? "system")
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 110),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        guard let panel, let screen = NSScreen.main else { return }
        panel.contentView = NSHostingView(
            rootView: QuickNoteView { [weak self] in self?.hide() }.modelContainer(container)
        )
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - 210, y: f.maxY - 130))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSSound(named: "Pop")?.play()
        CatWalker.shared.walk()
  }
    

    func hide() { panel?.orderOut(nil) }
}

// MARK: - Pop-up window
struct QuickNoteView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("language") private var language = "en"
    @State private var text = ""
    @FocusState private var focused: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🥷 " + tr("title", language)).font(.headline)
            TextField(tr("placeholder", language), text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            context.insert(Note(text: t))
            try? context.save()
        }
        onClose()
    }
}

// MARK: - Menu bar list + settings
struct NotesMenu: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @AppStorage("language") private var language = "en"
    @AppStorage("theme") private var theme = "system"
    @AppStorage("intervalMinutes") private var intervalMinutes = 120
    @AppStorage("nextPopup") private var nextPopup: Double = 0
    @State private var showSettings = false
    @State private var draftMinutes = 120
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("✏️ " + tr("newNote", language)) { PopupController.shared.show() }
            Button("🐈 Walk cat") { CatWalker.shared.walk() }
            Button("📝 Sticky note") { StickyNotes.shared.new() }
            Divider()

            if notes.isEmpty {
                Text(tr("noNotes", language)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.text)
                                Text(note.createdAt, style: .relative)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()
            ShieldView()
            Divider()
            Button("⚙️ " + tr("settings", language)) {
                draftMinutes = intervalMinutes
                showSettings.toggle()
            }

            if showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    // Pop-up interval
                    Text(tr("popupEvery", language)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Stepper("\(draftMinutes) \(tr("min", language))",
                                value: $draftMinutes, in: 1...600)
                        Spacer()
                        Button(saved ? tr("saved", language) : tr("save", language)) {
                            intervalMinutes = draftMinutes
                            PopupController.shared.reschedule()
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 6) {
                        ForEach([5, 15, 30, 60, 120], id: \.self) { m in
                            Button("\(m)") { draftMinutes = m }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    if nextPopup > 0 {
                        Text(tr("next", language) + " " +
                             Date(timeIntervalSince1970: nextPopup).formatted(date: .omitted, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Divider()

                    // Theme
                    Text(tr("theme", language)).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $theme) {
                        ForEach(themes, id: \.self) { Text(tr($0, language)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    // Language
                    Text(tr("language", language)).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $language) {
                        Text("English").tag("en")
                        Text("Čeština").tag("cs")
                        Text("Deutsch").tag("de")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Divider()
            Button(tr("quit", language)) { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 320)
        .onChange(of: theme) { _, newValue in applyTheme(newValue) }
    }
}
#endif
