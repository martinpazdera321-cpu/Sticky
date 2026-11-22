#if os(macOS)
import SwiftUI
import AppKit
import Security

struct ScanFinding: Identifiable {
    let id = UUID()
    let name: String
    let reason: String
    let url: URL?
}

// MARK: - Link checker (scam warning signs)
enum LinkChecker {
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

        // Fake brand check: e.g. paypal-login.xyz or apple.com.evil.ru
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

// MARK: - Downloads scanner
enum FileScanner {
    static let scriptExt = ["command", "sh", "scpt", "jar", "exe", "msi", "bat", "js", "vbs"]
    static let docExt = ["pdf", "doc", "docx", "jpg", "jpeg", "png", "txt", "xls", "xlsx", "mp4", "mp3"]

    static func scanDownloads() -> [ScanFinding] {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [ScanFinding(name: "Downloads", reason: "No access to the Downloads folder (check Step 1)", url: nil)]
        }
        var out: [ScanFinding] = []
        for f in files {
            let name = f.lastPathComponent
            let ext = f.pathExtension.lowercased()
            let parts = name.lowercased().split(separator: ".").map(String.init)

            // invoice.pdf.app → pretends to be a document
            if parts.count >= 3, docExt.contains(parts[parts.count - 2]), !docExt.contains(ext) {
                out.append(ScanFinding(name: name, reason: "Fake double extension, pretends to be .\(parts[parts.count - 2])", url: f))
                continue
            }
            if ext == "app" && !isSigned(f) {
                out.append(ScanFinding(name: name, reason: "App is not signed by a verified developer", url: f))
                continue
            }
            if scriptExt.contains(ext) {
                out.append(ScanFinding(name: name, reason: "Script or Windows program, only open if you trust the source", url: f))
            }
        }
        return out
    }

    static func isSigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil) == errSecSuccess
    }
}

// MARK: - Shield panel in the menu
struct ShieldView: View {
    @AppStorage("shieldOn") private var shieldOn = true
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

                // Downloads scan
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
    }

    private func checkLink() {
        guard !link.isEmpty else { return }
        linkResult = LinkChecker.check(link)
    }

    private func scan() {
        scanning = true
        scanned = false
        CatWalker.shared.startScanning()          // cat walks while scanning
        Task {
            try? await Task.sleep(for: .seconds(4))
            findings = FileScanner.scanDownloads()
            scanning = false
            scanned = true
            CatWalker.shared.stopScanning()       // cat finishes and leaves
        }
    }
}
#endif
