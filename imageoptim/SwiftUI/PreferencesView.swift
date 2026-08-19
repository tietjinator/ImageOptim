//
//  PreferencesView.swift
//  ImageOptim
//
//  SwiftUI replacement for Base.lproj/PrefsController.xib. Every control below is bound,
//  via @AppStorage, to the exact same NSUserDefaults key the old xib used (see
//  imageoptim/defaults.plist and the `keyPath="values.*"` bindings that used to live in the
//  xib), so no migration is needed and the app stays interoperable with defaults set outside
//  the UI (e.g. `defaults write net.pornel.ImageOptim RunLowPriority -bool false`).
//
//  Tab structure (General / Quality / Optimization speed) mirrors the original xib, which
//  grouped controls by *what they affect* rather than by file format. The "Performance"
//  section in General is new: RunLowPriority/RunConcurrent*/BounceDock existed as defaults
//  before but were never exposed in any xib.
//
//  Not carried over from the xib: the six per-tool "?" help buttons (they opened anchors in
//  the help book via tags 1-6).
//
//  General tab layout mirrors the original's two-pane arrangement (a single-column "Enable"
//  list, in the original's exact top-to-bottom order — extracted from each checkbox's real y
//  frame in the old xib, not just document order) beside the metadata/writing/performance
//  sections, rather than the first pass's arbitrary two-per-row grid.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var tabSelection: PreferencesTabSelection

    var body: some View {
        TabView(selection: $tabSelection.selectedTab) {
            GeneralTab()
                .tabItem { Text("General") }
                .tag(PreferencesTab.general)

            QualityTab()
                .tabItem { Text("Quality") }
                .tag(PreferencesTab.quality)

            OptimizationSpeedTab()
                .tabItem { Text("Optimization speed") }
                .tag(PreferencesTab.speed)
        }
        .padding(20)
        .frame(width: 620, height: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
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

    @AppStorage("PngOutRemoveChunks") private var pngOutRemoveChunks = true
    @AppStorage("JpegTranStripAll") private var jpegTranStripAll = true
    @AppStorage("JpegTranStripAllSetByGuetzli") private var jpegTranStripAllSetByGuetzli = false

    @AppStorage("PreservePermissions") private var preservePermissions = true
    @AppStorage("PreserveDates") private var preserveDates = false

    @AppStorage("RunLowPriority") private var runLowPriority = false
    @AppStorage("RunConcurrentFiles") private var runConcurrentFiles = 4
    @AppStorage("RunConcurrentDirscans") private var runConcurrentDirscans = 2
    @AppStorage("BounceDock") private var bounceDock = true

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
        HStack(alignment: .top, spacing: 32) {
            // Single column, in the original's real top-to-bottom order (recovered from each
            // checkbox's y frame in Base.lproj/PrefsController.xib, not document order).
            VStack(alignment: .leading, spacing: 6) {
                Text("Enable")
                    .font(.headline)
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
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Metadata and color profiles")
                        .font(.headline)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Writing files to disk")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Preserve file permissions, attributes and hardlinks", isOn: $preservePermissions)
                        Text("Saving to network drives is faster when permissions are not preserved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Preserve file creation and modification dates", isOn: $preserveDates)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Performance")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Run in low priority", isOn: $runLowPriority)
                        Text("On Apple Silicon this confines compression to the slow efficiency cores — leave off unless you need ImageOptim to stay out of the way of other work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Concurrent files: \(runConcurrentFiles)", value: $runConcurrentFiles, in: 1...16)
                    Stepper("Concurrent folder scans: \(runConcurrentDirscans)", value: $runConcurrentDirscans, in: 1...8)
                    Toggle("Bounce dock icon when done", isOn: $bounceDock)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
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
        .onChange(of: jpegTranStripAll) { stillStrippingAll in
            if guetzliEnabled, !stillStrippingAll {
                jpegTranStripAllSetByGuetzli = false
                guetzliEnabled = false
            }
        }
        .alert("Guetzli is very slow", isPresented: $showGuetzliSlownessWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It can take up to 30 minutes per image. Your system may be unresponsive while Guetzli is running.")
        }
    }
}

// MARK: - Quality

private struct QualityTab: View {
    @AppStorage("LossyEnabled") private var lossyEnabled = false
    @AppStorage("PngMinQuality") private var pngMinQuality = 80
    @AppStorage("JpegOptimEnabled") private var jpegOptimEnabled = true
    @AppStorage("JpegOptimMaxQuality") private var jpegMaxQuality = 80
    @AppStorage("GifQuality") private var gifQuality = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Enable lossy minification", isOn: $lossyEnabled)
                Text("Makes files much smaller, but may change how images look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // JPEG full-width above PNG/GIF side by side, matching the original layout.
            QualitySliderRow(
                title: "JPEG quality",
                value: Binding(get: { Double(jpegMaxQuality) }, set: { jpegMaxQuality = Int($0) }),
                minLabel: "50%", maxLabel: "99%"
            )
            .disabled(!lossyEnabled || !jpegOptimEnabled)

            HStack(alignment: .top, spacing: 32) {
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
        .padding(.top, 8)
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
                    .frame(width: 90, alignment: .leading)
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
            .padding(.leading, 94)
            .padding(.trailing, 34)
        }
    }
}

// MARK: - Optimization speed

private struct OptimizationSpeedTab: View {
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
        .padding(.top, 8)
    }
}
