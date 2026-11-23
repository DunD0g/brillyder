import SwiftUI
import UniformTypeIdentifiers
import BrillyDerCore

private struct BrillyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public struct CockpitSettingsSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDoc: BrillyBackupDocument? = nil
    @State private var backupNotice: String? = nil

    public var body: some View {
        @Bindable var bindableStore = store

        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - 1. Surface Appearance (Liquid Glass | Cosmic Minimalist)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("UI SURFACE STYLE")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            ForEach(SurfaceStyle.allCases) { style in
                                let selected = store.surfaceStyle == style
                                Button {
                                    withAnimation(.spring(duration: 0.35)) {
                                        store.surfaceStyle = style
                                    }
                                    store.triggerHaptic(.move)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: style == .liquidGlass ? "sparkles.rectangle.stack.fill" : "moon.stars.fill")
                                            .font(.title3)
                                            .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                            .frame(width: 30)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(style.title)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Text(style.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(selected ? 0.10 : 0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(selected ? BrillyPalette.brillyTeal.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                        // MARK: - 2. Copy Vibe & Engine Depth
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Coach Vibe")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Spacer()
                                Picker("Vibe", selection: $bindableStore.vibeMode) {
                                    ForEach(VibeMode.allCases) { v in
                                        Text(v.title).tag(v)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            HStack {
                                Text("Analysis Depth")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Spacer()
                                Picker("Depth", selection: $bindableStore.analysisPreset) {
                                    ForEach(AnalysisDepthPreset.allCases) { p in
                                        Text(p.title).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 210)
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            Toggle(isOn: $bindableStore.hapticsEnabled) {
                                Text("Tactile Haptics")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 3. Board Theme Swatches
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BOARD THEME")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(BoardThemeID.allCases) { theme in
                                    let selected = store.boardTheme == theme
                                    Button {
                                        store.boardTheme = theme
                                        store.triggerHaptic(.move)
                                    } label: {
                                        HStack(spacing: 10) {
                                            HStack(spacing: 0) {
                                                theme.lightSquare.frame(width: 16, height: 24)
                                                theme.darkSquare.frame(width: 16, height: 24)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                            Text(theme.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Spacer()
                                            if selected {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(theme.accent)
                                            }
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(selected ? 0.12 : 0.04))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(selected ? theme.accent : Color.white.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 4. Local-First Web <-> iOS JSON Backup
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LOCAL VAULT & WEB BACKUP")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            Text("100% on-device storage. Export or import JSON backups seamlessly between BrillyDer Web PWA and BrillyDer iOS.")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            HStack(spacing: 10) {
                                Button {
                                    if let data = try? store.exportBackupData() {
                                        exportDoc = BrillyBackupDocument(data: data)
                                        showingExporter = true
                                    }
                                } label: {
                                    Label("Export JSON", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showingImporter = true
                                } label: {
                                    Label("Import JSON", systemImage: "square.and.arrow.down")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                                }
                                .buttonStyle(.plain)
                            }

                            if let notice = backupNotice {
                                Text(notice)
                                    .font(.caption)
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(store.copy(cosmic: "Cockpit Settings", classic: "Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDoc,
                contentType: .json,
                defaultFilename: "brillyder-backup"
            ) { result in
                if case .success = result {
                    backupNotice = "Backup exported cleanly."
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let mergedCount = try store.importBackupData(data)
                        backupNotice = "Merged \(mergedCount) records from backup."
                    } catch {
                        backupNotice = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let err):
                    backupNotice = "Import cancelled: \(err.localizedDescription)"
                }
            }
        }
    }
}
