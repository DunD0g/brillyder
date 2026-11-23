import SwiftUI
import UniformTypeIdentifiers
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var backupError: Bool = false

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

                        // MARK: - 2. Copy Vibe, Engine Depth, Sound, Haptics & Celebrations
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Coach Vibe")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Picker("Vibe", selection: $bindableStore.vibeMode) {
                                    ForEach(VibeMode.allCases) { v in
                                        Text(v.title).tag(v)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Analysis Depth")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Picker("Depth", selection: $bindableStore.analysisPreset) {
                                    ForEach(AnalysisDepthPreset.allCases) { p in
                                        Text(p.title).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            Toggle(isOn: $bindableStore.soundEnabled) {
                                Text("Board & Coach Audio")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)

                            Toggle(isOn: $bindableStore.hapticsEnabled) {
                                Text("Tactile Haptics")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)

                            Toggle(isOn: $bindableStore.celebrationsEnabled) {
                                Text(store.copy(cosmic: "Cosmic UFO Celebrations", classic: "Move Celebrations"))
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

                        // MARK: - 4. Port Data From Web App (JSON Backup Export / Import / Paste)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PORT DATA FROM WEB APP (JSON BACKUP)")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            Text("In BrillyDer Web → Settings → Export JSON, save to Files (or AirDrop to iPhone), then tap Import File below to merge analyzed games, FSRS opening progress, custom courses, Woodpecker cycles, bookmarks & streaks.")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            HStack(spacing: 10) {
                                Button {
                                    showingImporter = true
                                } label: {
                                    Label("Import File", systemImage: "square.and.arrow.down")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    do {
                                        let data = try store.exportBackupData()
                                        exportDoc = BrillyBackupDocument(data: data)
                                        showingExporter = true
                                    } catch {
                                        backupError = true
                                        backupNotice = "Export failed: \(error.localizedDescription)"
                                    }
                                } label: {
                                    Label("Export JSON", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                                }
                                .buttonStyle(.plain)
                            }

                            #if canImport(UIKit) && os(iOS)
                            Button {
                                if let text = UIPasteboard.general.string,
                                   let data = text.data(using: .utf8) {
                                    do {
                                        let summary = try store.importBackupData(data)
                                        backupError = false
                                        backupNotice = summary.humanSummary
                                    } catch {
                                        backupError = true
                                        backupNotice = error.localizedDescription
                                    }
                                } else {
                                    backupError = true
                                    backupNotice = "Clipboard does not contain a BrillyDer JSON backup."
                                }
                            } label: {
                                Label("Import Backup From Clipboard", systemImage: "doc.on.clipboard")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            #endif

                            if let notice = backupNotice {
                                Text(notice)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(backupError ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
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
                switch result {
                case .success:
                    backupError = false
                    backupNotice = "Backup exported cleanly."
                case .failure(let err):
                    backupError = true
                    backupNotice = "Export failed: \(err.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let summary = try store.importBackupData(data)
                        backupError = false
                        backupNotice = summary.humanSummary
                    } catch {
                        backupError = true
                        backupNotice = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let err):
                    backupError = true
                    backupNotice = "Import cancelled: \(err.localizedDescription)"
                }
            }
        }
    }
}
