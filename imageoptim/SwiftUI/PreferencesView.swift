//
//  PreferencesView.swift
//  ImageOptim
//
//  SwiftUI replacement for Base.lproj/PrefsController.xib. Every control below is bound,
//  via @AppStorage, to the exact same NSUserDefaults key the old xib used (see
//  imageoptim/defaults.plist and the `keyPath="values.*"` bindings that used to live in the
//  xib), so no migration is needed and the app stays interoperable with defaults set outside
//  the UI (e.g. `defaults write com.tietjinator.SwiftOptim RunLowPriority -bool false`).
//
//  Layout is a sidebar of icon+label panes rather than the original's three-tab strip,
//  styled after IINA's Preferences window (https://github.com/iina/iina) at the user's
//  request: a selection-highlighted list on the left, grouped content on the right. IINA has
//  ~10 categories for a much bigger app; this splits ImageOptim's ~19 settings into 6 panes
//  that map onto what's actually here rather than forcing IINA's exact category set — the old
//  "General" tab in particular was two unrelated things (the tool Enable list and three
//  separate sections) crammed into one view, and reads better split into Tools/Metadata/
//  Files/Performance.
//
//  Not carried over from the xib: the six per-tool "?" help buttons (they opened anchors in
//  the help book via tags 1-6).
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var tabSelection: PreferencesTabSelection

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $tabSelection.selectedTab)
                .frame(width: 170)

            Divider()

            ScrollView {
                paneContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 680, height: 460)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch tabSelection.selectedTab {
        case .tools: ToolsPane()
        case .metadata: MetadataPane()
        case .files: FilesPane()
        case .performance: PerformancePane()
        case .quality: QualityPane()
        case .speed: SpeedPane()
        }
    }
}

// MARK: - Sidebar

private struct SidebarItem: Identifiable {
    let id: PreferencesTab
    let title: String
    let systemImage: String
}

private let sidebarItems: [SidebarItem] = [
    .init(id: .tools, title: "Tools", systemImage: "checklist"),
    .init(id: .metadata, title: "Metadata", systemImage: "tag"),
    .init(id: .files, title: "Files", systemImage: "folder"),
    .init(id: .performance, title: "Performance", systemImage: "bolt"),
    .init(id: .quality, title: "Quality", systemImage: "slider.horizontal.3"),
    .init(id: .speed, title: "Speed", systemImage: "speedometer"),
]

private struct SidebarView: View {
    @Binding var selection: PreferencesTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sidebarItems) { item in
                SidebarRow(item: item, isSelected: selection == item.id) {
                    selection = item.id
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                Text(item.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pane chrome

private struct PaneHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.bottom, 4)
    }
}

// MARK: - Tools

private struct ToolsPane: View {
    @AppStorage("GifsicleEnabled") private var gifsicleEnabled = true
    @AppStorage("PngOutEnabled") private var pngOutEnabled = true
    @AppStorage("OptiPngEnabled") private var oxiPngEnabled = true // key predates the OxiPNG rename
    @AppStorage("AdvPngEnabled") private var advPngEnabled = true
    @AppStorage("PngCrush2Enabled") private var pngCrushEnabled = false
    @AppStorage("ZopfliEnabled") private var zopfliEnabled = true
    @AppStorage("JpegOptimEnabled") private var jpegOptimEnabled = true
    @AppStorage("JpegTranEnabled") private var jpegTranEnabled = true
    @AppStorage("SvgoEnabled") private var svgoEnabled = true
    @AppStorage("SvgcleanerEnabled") private var svgcleanerEnabled = true
    @AppStorage("GuetzliEnabled") private var guetzliEnabled = false

    // Shadow storage for the Guetzli <-> strip-all-metadata coupling: the real toggle for this
    // key is shown in MetadataPane, but the side effect needs to happen wherever Guetzli's
    // own toggle lives. Both @AppStorage instances read/write the same NSUserDefaults key, so
    // this stays consistent regardless of which pane is on screen when either changes.
    @AppStorage("JpegTranStripAll") private var jpegTranStripAll = true
    @AppStorage("JpegTranStripAllSetByGuetzli") private var jpegTranStripAllSetByGuetzli = false

    @State private var showGuetzliSlownessWarning = false
    @State private var hasWarnedAboutGuetzli = false

    // Mirrors SvgoWorker's own node lookup (imageoptim/Backend/Workers/SvgoWorker.m):
    // SVGO isn't bundled, it shells out to a system Node install at one of these paths.
    private static var nodeIsInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: "/usr/local/bin/node")
            || fm.isExecutableFile(atPath: "/opt/homebrew/bin/node")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaneHeader(title: "Tools")
            Toggle("Zopfli", isOn: $zopfliEnabled)
            Toggle("PNGOUT", isOn: $pngOutEnabled)
            Toggle("OxiPNG", isOn: $oxiPngEnabled)
            Toggle("AdvPNG", isOn: $advPngEnabled)
            Toggle("PNGCrush", isOn: $pngCrushEnabled)
            Toggle("JPEGOptim", isOn: $jpegOptimEnabled)
            Toggle("Jpegtran", isOn: $jpegTranEnabled)
            Toggle("Guetzli", isOn: $guetzliEnabled)
            Toggle("Gifsicle", isOn: $gifsicleEnabled)
            Toggle("SVGO", isOn: $svgoEnabled)
                .disabled(!Self.nodeIsInstalled)
                .help(Self.nodeIsInstalled ? "" : "SVGO requires Node.js (install via Homebrew: brew install node)")
            Toggle("svgcleaner", isOn: $svgcleanerEnabled)
        }
        .onChange(of: guetzliEnabled) { isEnabled in
            guard isEnabled else {
                if jpegTranStripAllSetByGuetzli {
                    jpegTranStripAllSetByGuetzli = false
                    jpegTranStripAll = false
                }
                return
            }

            if !hasWarnedAboutGuetzli {
                hasWarnedAboutGuetzli = true
                showGuetzliSlownessWarning = true
            }
            if !jpegTranStripAll {
                jpegTranStripAllSetByGuetzli = true
                jpegTranStripAll = true
            }
        }
        .alert("Guetzli is very slow", isPresented: $showGuetzliSlownessWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It can take up to 30 minutes per image. Your system may be unresponsive while Guetzli is running.")
        }
    }
}

// MARK: - Metadata

private struct MetadataPane: View {
    @AppStorage("PngOutRemoveChunks") private var pngOutRemoveChunks = true
    @AppStorage("JpegTranStripAll") private var jpegTranStripAll = true

    // Shadow storage — see ToolsPane's comment on the same coupling from the other side.
    @AppStorage("GuetzliEnabled") private var guetzliEnabled = false
    @AppStorage("JpegTranStripAllSetByGuetzli") private var jpegTranStripAllSetByGuetzli = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Metadata")

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Strip PNG metadata (gamma, color profiles, optional chunks)", isOn: $pngOutRemoveChunks)
                Text("Web browsers require gamma chunks to be removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Strip JPEG metadata (EXIF, color profiles, GPS, rotation, etc.)", isOn: $jpegTranStripAll)
                Text("Not recommended if you rely on embedded copyright information")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: jpegTranStripAll) { stillStrippingAll in
            if guetzliEnabled, !stillStrippingAll {
                jpegTranStripAllSetByGuetzli = false
                guetzliEnabled = false
            }
        }
    }
}

// MARK: - Files

private struct FilesPane: View {
    @AppStorage("PreservePermissions") private var preservePermissions = true
    @AppStorage("PreserveDates") private var preserveDates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Files")

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Preserve file permissions, attributes and hardlinks", isOn: $preservePermissions)
                Text("Saving to network drives is faster when permissions are not preserved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Preserve file creation and modification dates", isOn: $preserveDates)
        }
    }
}

// MARK: - Performance

private struct PerformancePane: View {
    @AppStorage("RunLowPriority") private var runLowPriority = false
    @AppStorage("RunConcurrentFiles") private var runConcurrentFiles = 4
    @AppStorage("RunConcurrentDirscans") private var runConcurrentDirscans = 2
    @AppStorage("BounceDock") private var bounceDock = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Performance")

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Run in low priority", isOn: $runLowPriority)
                Text("On Apple Silicon this confines compression to the slow efficiency cores — leave off unless you need ImageOptim to stay out of the way of other work")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Stepper("Concurrent files: \(runConcurrentFiles)", value: $runConcurrentFiles, in: 1...16)
            Stepper("Concurrent folder scans: \(runConcurrentDirscans)", value: $runConcurrentDirscans, in: 1...8)
            Toggle("Bounce dock icon when done", isOn: $bounceDock)
        }
    }
}

// MARK: - Quality

private struct QualityPane: View {
    @AppStorage("LossyEnabled") private var lossyEnabled = false
    @AppStorage("PngMinQuality") private var pngMinQuality = 80
    @AppStorage("JpegOptimEnabled") private var jpegOptimEnabled = true
    @AppStorage("JpegOptimMaxQuality") private var jpegMaxQuality = 80
    @AppStorage("GifQuality") private var gifQuality = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Quality")

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Enable lossy minification", isOn: $lossyEnabled)
                Text("Makes files much smaller, but may change how images look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            QualitySliderRow(
                title: "JPEG quality",
                value: Binding(get: { Double(jpegMaxQuality) }, set: { jpegMaxQuality = Int($0) }),
                minLabel: "50%", maxLabel: "99%"
            )
            .disabled(!lossyEnabled || !jpegOptimEnabled)

            QualitySliderRow(
                title: "PNG quality",
                value: Binding(get: { Double(pngMinQuality) }, set: { pngMinQuality = Int($0) }),
                minLabel: "40%", maxLabel: "100%"
            )
            .disabled(!lossyEnabled)

            QualitySliderRow(
                title: "GIF quality",
                value: Binding(get: { Double(gifQuality) }, set: { gifQuality = Int($0) }),
                minLabel: "40%", maxLabel: "100%"
            )
            .disabled(!lossyEnabled)
        }
    }
}

// macOS-12-compatible stand-in for LabeledContent (introduced in macOS 13), extended with the
// current-value readout and min/max tick labels the original's AppKit slider showed natively.
private struct QualitySliderRow: View {
    let title: String
    @Binding var value: Double
    let minLabel: String
    let maxLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .frame(width: 80, alignment: .leading)
                Slider(value: $value, in: 0...100, step: 1)
                Text("\(Int(value))%")
                    .frame(width: 34, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 84)
            .padding(.trailing, 34)
        }
    }
}

// MARK: - Speed

private struct SpeedPane: View {
    @AppStorage("AdvPngLevel") private var advPngLevel: Double = 4

    private var levelLabel: String {
        switch advPngLevel {
        case ..<1.5: return "Fast"
        case ..<3.5: return "Normal"
        case ..<5.5: return "Extra"
        default: return "Insane"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Speed")

            HStack {
                Text("Optimization level")
                Spacer()
                Text(levelLabel).foregroundStyle(.secondary)
            }
            // Plain Slider (no label/minimumValueLabel/maximumValueLabel closures): on macOS,
            // unlike iOS, that "label" closure renders as a second visible title next to the
            // slider rather than staying accessibility-only — using it duplicated "Optimization
            // level" on screen. Four hand-laid-out labels below instead, matching the
            // original's evenly spaced Fast/Normal/Extra/Insane row under its 7-tick slider.
            Slider(value: $advPngLevel, in: 0...6, step: 1)
            HStack {
                Text("Fast")
                Spacer()
                Text("Normal")
                Spacer()
                Text("Extra")
                Spacer()
                Text("Insane")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
