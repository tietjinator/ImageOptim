//
//  FileRowStore.swift
//  ImageOptim
//
//  Per-row observable wrapper around a single JobProxy (imageoptim/JobProxy.h/.m).
//
//  Why this exists: FileListStore's `rows` array only changes identity when
//  FilesController's `arrangedObjects` KVO fires (insert/remove/reorder). It does NOT refire
//  when an individual JobProxy's own properties change in place — and that in-place mutation
//  is literally how compression progress is reported (JobProxy re-publishes its underlying
//  Job's KVO notifications for statusText/byteSizeOptimized/percentOptimized/etc., see
//  JobProxy.m's -observeValueForKeyPath:). The old NSTableView got this via per-cell Cocoa
//  Bindings on `arrangedObjects.<key>`; this is the SwiftUI equivalent — one KVO observer per
//  row, republished as @Published so a row's SwiftUI content re-renders on its own.
//
//  Deliberately NOT observed here: isBusy/isDone/isFailed/isStoppable/isOptimized/canRevert.
//  JobProxy's own +propertiesToProxy list (JobProxy.m) doesn't include them either — the old
//  UI never observed them continuously (only `statusImageName`, which already reflects
//  done/failed/in-progress as an icon). They're read fresh on demand instead, matching how
//  menu validation already works (-[FilesController canStartAgainOptimized:] etc. are called
//  synchronously when a menu opens, not cached).
//

import Combine
import Foundation

private let observedKeyPaths = [
    "fileName", "statusText", "statusImageName",
    "byteSizeOriginal", "byteSizeOptimized", "percentOptimized", "bestToolName",
]

@MainActor
final class FileRowStore: NSObject, ObservableObject, Identifiable {
    nonisolated let id: ObjectIdentifier
    let jobProxy: JobProxy

    @Published private(set) var fileName: String = ""
    @Published private(set) var statusText: String?
    @Published private(set) var statusImageName: String?
    @Published private(set) var byteSizeOriginal: Int = 0
    @Published private(set) var byteSizeOptimized: Int = 0
    @Published private(set) var percentOptimized: Double = 0
    @Published private(set) var bestToolName: String?

    private var isObserving = false

    init(jobProxy: JobProxy) {
        self.jobProxy = jobProxy
        self.id = ObjectIdentifier(jobProxy)
        super.init()

        refresh()
        for keyPath in observedKeyPaths {
            jobProxy.addObserver(self, forKeyPath: keyPath, options: [], context: nil)
        }
        isObserving = true
    }

    deinit {
        guard isObserving else { return }
        for keyPath in observedKeyPaths {
            jobProxy.removeObserver(self, forKeyPath: keyPath)
        }
    }

    private func refresh() {
        fileName = jobProxy.fileName
        statusText = jobProxy.statusText
        statusImageName = jobProxy.statusImageName
        // JobProxy.h declares these three NSNumber* non-nullable (no `nullable` inside its
        // NS_ASSUME_NONNULL block), but JobProxy.m's -byteSizeOriginal/-byteSizeOptimized/
        // -percentOptimized can genuinely return nil via nullToNil() — a pre-existing
        // header/implementation mismatch, not something to "fix" here (out of scope: JobProxy
        // is shared plumbing, not this rewrite's UI layer). Not calling .intValue/.doubleValue
        // through Swift Optional chaining (the compiler won't allow it on a "non-optional"
        // type anyway) is safe here specifically because NSNumber's accessors are ordinary
        // Objective-C methods reached via objc_msgSend, and a message to nil returns a
        // zeroed scalar for int/double returns — i.e. exactly the 0 fallback wanted below.
        byteSizeOriginal = jobProxy.byteSizeOriginal.intValue
        byteSizeOptimized = jobProxy.byteSizeOptimized.intValue
        percentOptimized = jobProxy.percentOptimized.doubleValue
        bestToolName = jobProxy.bestToolName
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let keyPath, observedKeyPaths.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Formatted display (matches SavingsFormatter.m / the xib's byteCountFormatter)

    var byteCountFormattedOptimized: String {
        Self.byteCountFormatter.string(fromByteCount: Int64(byteSizeOptimized))
    }

    var savingsText: String {
        // Job.m's -percentOptimized returns nil ("early work in progress, don't display
        // anything") until it has a real optimized byte size to compare against — and, per
        // the note in -refresh() above, a nil percentOptimized reads back here as 0.0, which
        // is indistinguishable from a genuine 0% saving. Gating on byteSizeOptimized > 0
        // sidesteps that: it's nil/zero in exactly the same "not ready yet" window (there's
        // no such thing as a real 0-byte optimized image), so this reproduces the original's
        // blank-while-queued behavior without needing to interrogate NSNumber's nilness.
        guard byteSizeOptimized > 0 else {
            return ""
        }
        if percentOptimized < 1.0 / 1024.0 {
            return "0%"
        }
        return String(format: "%.1f%%", percentOptimized)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = .useBytes
        f.includesUnit = false
        f.allowsNonnumericFormatting = false
        return f
    }()
}
