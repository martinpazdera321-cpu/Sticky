#if os(macOS)
import SwiftUI
import AppKit
import Security

nonisolated struct ScanFinding: Identifiable {
    let id = UUID()
    let name: String
    let reason: String
    let url: URL?
}

// MARK: - Link checker (scam warning signs)
nonisolated enum LinkChecker {
    static let riskyTLDs = ["zip", "mov", "xyz", "top", "click", "gq", "tk", "ml", "cf", "work", "rest", "country", "kim"]
    static let brands = ["paypal", "apple", "google", "microsoft", "amazon", "facebook", "instagram",
                         "netflix", "revolut", "airbank", "csob", "ceskasporitelna", "moneta", "raiffeisen"]

    static func check(_ raw: String) -> [String] {
        var reasons: [String] = []
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), let host = url.host?.lowercased() else { return ["Not a valid link"] }
        let labels = host.split(separator: ".").map(String.init)

        if url.scheme == "http" { reasons.append("Not encrypted (http instead of https)") }
        if host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil {
            reasons.append("Uses a raw IP address instead of a name")
        }
        if host.contains("xn--") { reasons.append("Contains look-alike letters (punycode)") }
        if let tld = labels.last, riskyTLDs.contains(tld) { reasons.append("Ending .\(tld) is often used for scams") }
        if s.contains("@") { reasons.append("Contains @, which can hide the real address") }
        if labels.count > 4 { reasons.append("Unusually many subdomains") }
        if s.count > 150 { reasons.append("Very long link") }

        let realName = labels.count >= 2 ? labels[labels.count - 2] : host
        for label in labels {
            for token in label.split(separator: "-").map(String.init) where brands.contains(token) {
                if realName != token {
                    reasons.append("Pretends to be \(token), but the real site is \(realName)")
                    return reasons
                }
            }
        }
        return reasons
    }
}

// MARK: - File scanner
nonisolated enum FileScanner {
    static let scriptExt = ["command", "sh", "scpt", "jar", "exe", "msi", "bat", "js", "vbs"]
    static let docExt = ["pdf", "doc", "docx", "jpg", "jpeg", "png", "txt", "xls", "xlsx", "mp4", "mp3"]

    static var downloadsURL: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
    }

    static func listFiles() -> [URL]? {
        guard let dir = downloadsURL else { return nil }
        return try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }

    /// Checks one file. Returns a finding if it looks dangerous, nil if OK.
    static func check(_ f: URL) -> ScanFinding? {
        let name = f.lastPathComponent
        let ext = f.pathExtension.lowercased()
        let parts = name.lowercased().split(separator: ".").map(String.init)

        if parts.count >= 3, docExt.contains(parts[parts.count - 2]), !docExt.contains(ext) {
            return ScanFinding(name: name, reason: "Fake double extension, pretends to be .\(parts[parts.count - 2])", url: f)
        }
        if ext == "app" && !isSigned(f) {
            return ScanFinding(name: name, reason: "App is not signed by a verified developer", url: f)
        }
        if scriptExt.contains(ext) {
            return ScanFinding(name: name, reason: "Script or Windows program, only open if you trust the source", url: f)
        }
        return nil
    }

    static func scanDownloads() -> [ScanFinding] {
        guard let files = listFiles() else {
            return [ScanFinding(name: "Downloads", reason: "No access to the Downloads folder (check app permissions)", url: nil)]
        }
        return files.compactMap { check($0) }
    }

    static func isSigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil) == errSecSuccess
    }
}

// MARK: - Auto-scan: watches the Downloads folder
final class DownloadWatcher {
    static let shared = DownloadWatcher()
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var known: Set<String> = []
    private var pending: DispatchWorkItem?
    private let ignoredExt = ["crdownload", "download", "part", "tmp"]   // still downloading

    /// Starts or stops depending on the switches in the menu
    func startIfEnabled() {
        let shieldOn = UserDefaults.standard.object(forKey: "shieldOn") as? Bool ?? true
        let autoScan = UserDefaults.standard.object(forKey: "autoScan") as? Bool ?? true
        if shieldOn && autoScan { start() } else { stop() }
    }

    private func start() {
        guard source == nil, let dir = FileScanner.downloadsURL else { return }
        known = Set((FileScanner.listFiles() ?? []).map { $0.lastPathComponent })
        fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.folderChanged() }
        s.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        s.resume()
        source = s
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    private func folderChanged() {
        // wait 2 seconds so the download can finish
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkNewFiles() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func checkNewFiles() {
        let files = FileScanner.listFiles() ?? []
        let newFiles = files.filter {
            !known.contains($0.lastPathComponent) && !ignoredExt.contains($0.pathExtension.lowercased())
        }
        known = Set(files.map { $0.lastPathComponent })
        guard !newFiles.isEmpty else { return }

        CatWalker.shared.walk()                       // cat walks = scanning
        for f in newFiles {
            if let finding = FileScanner.check(f) { warn(finding) }
        }
    }

    private func warn(_ f: ScanFinding) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "🛡️ Sticky Shield warning"
        alert.informativeText = "\(f.name)\n\n\(f.reason)"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep")
        if alert.runModal() == .alertFirstButtonReturn, let u = f.url {
            try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
        }
    }
}

// MARK: - Shield panel in the menu
struct ShieldView: View {
    @AppStorage("shieldOn") private var shieldOn = true
    @AppStorage("autoScan") private var autoScan = true
    @State private var link = ""
    @State private var linkResult: [String]? = nil
    @State private var findings: [ScanFinding] = []
    @State private var scanning = false
    @State private var scanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("🛡️ MindNinja Shield", isOn: $shieldOn)
                .toggleStyle(.switch)

            if shieldOn {
                Toggle("Auto-scan new downloads", isOn: $autoScan)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                // Link check
                HStack {
                    TextField("Paste a link to check…", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(checkLink)
                    Button("Check", action: checkLink)
                }
                if let r = linkResult {
                    if r.isEmpty {
                        Text("✅ No warning signs found").font(.caption).foregroundStyle(.green)
                    } else {
                        ForEach(r, id: \.self) { reason in
                            Text("⚠️ " + reason).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                // Manual scan
                Button(scanning ? "🐈‍⬛ Scanning…" : "🔍 Scan Downloads") { scan() }
                    .disabled(scanning)

                if scanned && !scanning {
                    if findings.isEmpty {
                        Text("✅ Nothing suspicious in Downloads").font(.caption).foregroundStyle(.green)
                    }
                    ForEach(findings) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.caption.bold())
                                Text(f.reason).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let u = f.url {
                                Button("Trash") {
                                    try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
                                    findings.removeAll { $0.id == f.id }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: shieldOn) { _, _ in DownloadWatcher.shared.startIfEnabled() }
        .onChange(of: autoScan) { _, _ in DownloadWatcher.shared.startIfEnabled() }
    }

    private func checkLink() {
        guard !link.isEmpty else { return }
        linkResult = LinkChecker.check(link)
    }

    private func scan() {
        scanning = true
        scanned = false
        CatWalker.shared.startScanning()
        Task {
            try? await Task.sleep(for: .seconds(4))
            findings = FileScanner.scanDownloads()
            scanning = false
            scanned = true
            CatWalker.shared.stopScanning()
        }
    }
}
#endif
