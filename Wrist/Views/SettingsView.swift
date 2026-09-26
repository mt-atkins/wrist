import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var obsidian: ObsidianExporter
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pro.isPro ? "checkmark.seal.fill" : "sparkles")
                                .font(.title3)
                                .foregroundStyle(Theme.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pro.isPro ? "Wrist Pro" : "Unlock Wrist Pro")
                                    .font(.headline).foregroundStyle(Theme.paper)
                                Text(pro.isPro ? "Unlocked. Thank you." : "Ask, Reminders, Shortcuts, Obsidian, your own model, Whisper")
                                    .font(.footnote).foregroundStyle(Theme.softInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.machineGrey)
                        }
                        .panel(padding: 14)
                    }
                    .buttonStyle(.plain)

                    SectionLabel("Intelligence").padding(.top, 12)
                    NavigationLink { ModelsView() } label: {
                        row("Models", detail: modelSummary, symbol: "cpu")
                    }
                    .buttonStyle(.plain)

                    SectionLabel("Integrations").padding(.top, 12)
                    NavigationLink { ObsidianSettingsView() } label: {
                        row("Obsidian", detail: obsidian.vaultDisplayName.map { "Vault: \($0)" } ?? "Not connected", symbol: "books.vertical")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { MCPView() } label: {
                        row("MCP for Claude & agents", detail: "Search captures from Claude Desktop or Claude Code", symbol: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.plain)

                    SectionLabel("Privacy").padding(.top, 12)
                    Text(privacyText)
                        .font(.footnote)
                        .foregroundStyle(Theme.softInk)
                        .panel(padding: 14)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var modelSummary: String {
        let transcription: String = switch settings.transcription {
        case .appleSpeech: "Apple Speech"
        case .whisper(let variant): WhisperModel.catalog.first { $0.variant == variant }?.name ?? "Whisper"
        }
        let summary = settings.summary == .byom ? settings.remoteConfig.displayName : settings.summary.label
        return "\(transcription) · \(summary)"
    }

    private var privacyText: String {
        if settings.summary == .byom {
            return "Transcription stays on your iPhone. Because you chose your own model, transcripts and Ask questions are sent to \(settings.remoteConfig.baseURL)."
        }
        return "Transcription and summaries run on your iPhone. Nothing is sent to a server."
    }

    private func row(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.paper)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.paper)
                Text(detail).font(.footnote).foregroundStyle(Theme.softInk).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.machineGrey)
        }
        .panel(padding: 14)
    }
}

// MARK: - Models (Handy-style picker)

struct ModelsView: View {
    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var whisper = WhisperModelStore.shared
    @State private var paywall: ProFeature?
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Transcription · on device")
                transcriptionCard(
                    title: "Apple Speech", size: "Built in", speed: 5, accuracy: 3,
                    note: "Free, instant, no download",
                    selected: settings.transcription == .appleSpeech, locked: false
                ) {
                    settings.transcription = .appleSpeech
                }
                ForEach(WhisperModel.catalog) { model in
                    whisperCard(model)
                }

                SectionLabel("Summaries & Ask").padding(.top, 16)
                VStack(spacing: 0) {
                    ForEach(Array(SummaryEngine.allCases.enumerated()), id: \.element) { index, engine in
                        Button {
                            if engine == .byom, !pro.isPro { paywall = .byom } else { settings.summary = engine }
                        } label: {
                            HStack {
                                Image(systemName: settings.summary == engine ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(settings.summary == engine ? Theme.orange : Theme.machineGrey)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(engine.label).foregroundStyle(Theme.paper)
                                    Text(detail(for: engine)).font(.caption).foregroundStyle(Theme.softInk)
                                }
                                Spacer()
                                if engine == .byom, !pro.isPro { ProBadge() }
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < SummaryEngine.allCases.count - 1 {
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                    }
                }
                .panel(padding: 0)

                if settings.summary == .byom, pro.isPro {
                    byomForm
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywall) { PaywallView(highlight: $0) }
        .onAppear { apiKey = settings.apiKey ?? "" }
    }

    private func detail(for engine: SummaryEngine) -> String {
        switch engine {
        case .automatic: Summarizer.usesAppleIntelligence ? "Apple Intelligence on this iPhone" : "Local rules (Apple Intelligence unavailable)"
        case .appleIntelligence: Summarizer.usesAppleIntelligence ? "On-device model" : "Not available on this iPhone"
        case .rules: "Keyword rules. Fast, private, basic"
        case .byom: "Claude, OpenAI, or a local model on your Mac"
        }
    }

    // MARK: Whisper cards

    private func whisperCard(_ model: WhisperModel) -> some View {
        let state = whisper.state(of: model)
        let selected = settings.transcription == .whisper(variant: model.variant)
        return transcriptionCard(
            title: model.name, size: model.size, speed: model.speed, accuracy: model.accuracy,
            note: model.note, selected: selected, locked: !pro.isPro
        ) {
            guard pro.isPro else { paywall = .whisper; return }
            if state == .ready { settings.transcription = .whisper(variant: model.variant) }
        } trailing: {
            switch state {
            case .notDownloaded, .failed:
                Button {
                    if pro.isPro { whisper.download(model) } else { paywall = .whisper }
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Theme.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download \(model.name)")
            case .downloading(let fraction):
                Button { whisper.cancel(model) } label: {
                    ZStack {
                        Circle().stroke(Theme.line, lineWidth: 3)
                        Circle().trim(from: 0, to: fraction).stroke(Theme.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "stop.fill").font(.system(size: 8)).foregroundStyle(Theme.paper)
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download, \(Int(fraction * 100)) percent")
            case .ready:
                Menu {
                    Button("Delete model", systemImage: "trash", role: .destructive) { whisper.delete(model) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.machineGrey).frame(width: 24, height: 24)
                }
            }
        } footer: {
            if case .failed(let message) = state {
                Text(message).font(.caption).foregroundStyle(Theme.red)
            }
        }
    }

    private func transcriptionCard<Trailing: View, Footer: View>(
        title: String, size: String, speed: Int, accuracy: Int, note: String,
        selected: Bool, locked: Bool, select: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Theme.orange : Theme.machineGrey)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.paper)
                                if locked { ProBadge() }
                            }
                            Text("\(size) · \(note)").font(.caption).foregroundStyle(Theme.softInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing()
            }
            HStack(spacing: 16) {
                meter("Speed", speed)
                meter("Accuracy", accuracy)
            }
            .padding(.leading, 30)
            footer()
        }
        .panel(padding: 14)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).stroke(selected ? Theme.orange : .clear, lineWidth: 1))
    }

    private func meter(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 6) {
            SectionLabel(label)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Capsule().fill(i <= value ? Theme.paper : Theme.line).frame(width: 10, height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) of 5")
    }

    // MARK: BYOM

    private var byomForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Provider", selection: Binding(get: { settings.provider }, set: { settings.selectProvider($0); apiKey = settings.apiKey ?? "" })) {
                ForEach(ModelProvider.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            field("Server", text: $settings.baseURL, prompt: settings.provider.defaultBaseURL, keyboard: .URL)
            field("Model", text: $settings.model, prompt: settings.provider == .anthropic ? "claude-opus-5" : "model name", keyboard: .default)
            if settings.provider.requiresKey || settings.provider == .openAICompatible {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(settings.provider.requiresKey ? "API key" : "API key (optional)")
                    SecureField("Stored in your iPhone's Keychain", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { settings.apiKey = apiKey }
                        .padding(10)
                        .background(Theme.graphite, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .foregroundStyle(Theme.paper)
                }
            }
            if settings.provider == .openAICompatible {
                Text("Running Ollama or LM Studio on your Mac? Use its network address, e.g. http://192.168.1.10:11434/v1 (Ollama) or :1234/v1 (LM Studio), and allow Local Network access when asked.")
                    .font(.caption).foregroundStyle(Theme.softInk)
            }
            HStack {
                Button {
                    settings.apiKey = apiKey
                    Task { await test() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Save & test")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Theme.orange, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)
                if let testResult {
                    Text(testResult).font(.caption).foregroundStyle(testResult.hasPrefix("✓") ? Theme.green : Theme.red)
                }
            }
            Text("Transcripts and Ask questions are sent to this server. Your key never leaves this iPhone except to authenticate with it.")
                .font(.caption).foregroundStyle(Theme.machineGrey)
        }
        .panel(padding: 14)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.graphite, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .foregroundStyle(Theme.paper)
        }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let insight = try await RemoteModel.summarize(
                "Quick test. Remind me to water the plants tomorrow morning.",
                config: settings.remoteConfig
            )
            testResult = "✓ \(insight.title)"
        } catch {
            testResult = error.localizedDescription
        }
    }
}

// MARK: - Obsidian

struct ObsidianSettingsView: View {
    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var obsidian: ObsidianExporter
    @EnvironmentObject private var store: MemoStore
    @State private var picking = false
    @State private var showPaywall = false
    @State private var exportedCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each capture becomes a Markdown note in your vault, with frontmatter, a summary, to-dos as checkboxes (works with the Tasks plugin) and the full transcript. Ticking a to-do in Wrist updates the note.")
                    .font(.subheadline).foregroundStyle(Theme.softInk)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        StatusDot(color: obsidian.isConnected ? Theme.green : Theme.machineGrey)
                        Text(obsidian.vaultDisplayName.map { "Connected to \($0)" } ?? "No vault connected")
                            .foregroundStyle(Theme.paper)
                        Spacer()
                        if !pro.isPro { ProBadge() }
                    }
                    Button(obsidian.isConnected ? "Choose a different vault" : "Choose vault folder") {
                        if pro.isPro { picking = true } else { showPaywall = true }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("In the Files picker, open On My iPhone › Obsidian (or iCloud Drive › Obsidian) and select your vault folder.")
                        .font(.caption).foregroundStyle(Theme.machineGrey)
                }
                .panel(padding: 14)

                if obsidian.isConnected, pro.isPro {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Save captures automatically", isOn: $settings.obsidian.enabled)
                        labeled("Vault name (for Open in Obsidian)", text: $settings.obsidian.vaultName)
                        labeled("Folder for captures", text: $settings.obsidian.folder)
                        Toggle("Link each capture in the daily note", isOn: $settings.obsidian.linkInDailyNote)
                        if settings.obsidian.linkInDailyNote {
                            labeled("Daily notes folder", text: $settings.obsidian.dailyFolder)
                            labeled("Daily note date format", text: $settings.obsidian.dailyFormat)
                        }
                    }
                    .tint(Theme.orange)
                    .foregroundStyle(Theme.paper)
                    .panel(padding: 14)

                    HStack {
                        Button("Export all captures now") {
                            exportedCount = obsidian.exportAll(store.memos)
                        }
                        .font(.subheadline.weight(.semibold))
                        if let exportedCount { Text("\(exportedCount) exported").font(.caption).foregroundStyle(Theme.softInk) }
                        Spacer()
                        Button("Disconnect", role: .destructive) { obsidian.disconnect() }
                            .font(.subheadline)
                    }
                }

                if let error = obsidian.lastError {
                    Text(error).font(.footnote).foregroundStyle(Theme.red)
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Obsidian")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                obsidian.connect(vault: url)
                exportedCount = obsidian.exportAll(store.memos)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .obsidian) }
    }

    private func labeled(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            TextField(label, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.graphite, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
    }
}

// MARK: - MCP

struct MCPView: View {
    @EnvironmentObject private var settings: AppSettings

    private var config: String {
        """
        {
          "mcpServers": {
            "wrist": {
              "command": "node",
              "args": ["/path/to/wrist/mcp/dist/src/index.js", "--vault", "/path/to/your/vault/\(settings.obsidian.folder)"]
            }
          }
        }
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Give Claude Desktop, Claude Code or any MCP client access to your captures. The Wrist MCP server runs on your Mac and reads the notes Wrist saves to your Obsidian vault, so nothing extra leaves your devices.")
                    .font(.subheadline).foregroundStyle(Theme.softInk)

                SectionLabel("1 · Connect Obsidian").padding(.top, 8)
                Text("Turn on Obsidian export (Settings › Obsidian) and make sure the vault syncs to your Mac (iCloud Drive or Obsidian Sync).")
                    .font(.footnote).foregroundStyle(Theme.paper).panel(padding: 14)

                SectionLabel("2 · Add the server to your MCP client").padding(.top, 8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(config)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.paper)
                        .textSelection(.enabled)
                    Button("Copy config", systemImage: "doc.on.doc") { UIPasteboard.general.string = config }
                        .font(.footnote.weight(.semibold))
                }
                .panel(padding: 14)
                Text("Set up once on your Mac: git clone the Wrist repo, then run npm install in its mcp folder.\nClaude Code: claude mcp add wrist -- node /path/to/wrist/mcp/dist/src/index.js --vault \"/path/to/vault/\(settings.obsidian.folder)\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.softInk)
                    .textSelection(.enabled)

                SectionLabel("3 · Ask").padding(.top, 8)
                Text("“What did I promise Priya?” · “List my open to-dos from this week” · “Summarise what I captured about the launch.”")
                    .font(.footnote).foregroundStyle(Theme.paper).panel(padding: 14)

                SectionLabel("Tools").padding(.top, 8)
                Text("wrist_search_captures · wrist_get_capture · wrist_list_open_todos · wrist_recent_captures")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.softInk)
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("MCP")
        .navigationBarTitleDisplayMode(.inline)
    }
}
