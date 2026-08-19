//
//  FileListStore.swift
//  ImageOptim
//
//  SwiftUI-facing bridge over FilesController (imageoptim/FilesController.h/.m).
//  FilesController's properties are plain @property, not @objc dynamic, so Combine's
//  typed publisher(for:) isn't available here — this uses classic NSObject KVO
//  (addObserver:forKeyPath:) and republishes changes as @Published, the same pattern
//  FilesController itself already uses internally to watch its JobQueue's isBusy.
//

import AppKit
import Combine

// File-scope (not a type member) so it's usable from FileListStore's nonisolated deinit
// without tripping Swift 6's MainActor-isolation-of-static-members rule.
private let observedKeyPaths = ["arrangedObjects", "isBusy", "isStoppable", "selectionIndexes"]

@MainActor
@objc final class FileListStore: NSObject, ObservableObject {
    let filesController: FilesController
    private var isObserving = false
    private var rowCache: [ObjectIdentifier: FileRowStore] = [:]

    @Published private(set) var rows: [FileRowStore] = []
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var isStoppable: Bool = false

    // Mirrors FilesController.selectedObjects/selectionIndexes (standard NSArrayController
    // selection). Kept in sync so the rest of the app — Quick Look, Start Again/Stop/Revert,
    // menu validation in ImageOptimController.m — keeps working against "the selection"
    // exactly as it did when an NSTableView bound to FilesController drove that state.
    @Published var selection: Set<ObjectIdentifier> = [] {
        didSet {
            guard !isSyncingSelectionFromController, selection != oldValue else { return }
            let matched = rows.filter { selection.contains($0.id) }.map { $0.jobProxy }
            filesController.setSelectedObjects(matched)
        }
    }
    private var isSyncingSelectionFromController = false

    // Set from ImageOptimController.m's existing status-bar computation (see
    // -initStatusbarWithDefaults: in ImageOptimController.m), which stays in Objective-C
    // since it's a throttled/coalesced dispatch_source-driven computation over the file
    // list, not really "UI" — only where the result is displayed moves to SwiftUI.
    @objc @Published var statusText: String = ""
    @objc @Published var statusSelectable: Bool = false

    @objc init(filesController: FilesController) {
        self.filesController = filesController
        super.init()

        for keyPath in observedKeyPaths {
            filesController.addObserver(self, forKeyPath: keyPath, options: [.initial], context: nil)
        }
        isObserving = true
    }

    deinit {
        guard isObserving else { return }
        for keyPath in observedKeyPaths {
            filesController.removeObserver(self, forKeyPath: keyPath)
        }
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

        // KVO callbacks can arrive off the main thread; hop back on for @Published mutation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch keyPath {
            case "arrangedObjects":
                self.rebuildRows()
            case "isBusy":
                self.isBusy = self.filesController.isBusy
            case "isStoppable":
                self.isStoppable = self.filesController.isStoppable
            case "selectionIndexes":
                self.syncSelectionFromController()
            default:
                break
            }
        }
    }

    private func rebuildRows() {
        let proxies = (filesController.arrangedObjects as? [JobProxy]) ?? []
        var newCache: [ObjectIdentifier: FileRowStore] = [:]
        newCache.reserveCapacity(proxies.count)

        rows = proxies.map { proxy in
            let key = ObjectIdentifier(proxy)
            if let existing = rowCache[key] {
                newCache[key] = existing
                return existing
            }
            let created = FileRowStore(jobProxy: proxy)
            newCache[key] = created
            return created
        }
        rowCache = newCache

        // Drop selection entries for rows that no longer exist (e.g. after Clear Complete).
        let validIDs = Set(rows.map(\.id))
        if !selection.isSubset(of: validIDs) {
            selection.formIntersection(validIDs)
        }
    }

    private func syncSelectionFromController() {
        let selected = (filesController.selectedObjects as? [JobProxy]) ?? []
        let newSelection = Set(selected.map { ObjectIdentifier($0) })
        guard newSelection != selection else { return }
        isSyncingSelectionFromController = true
        selection = newSelection
        isSyncingSelectionFromController = false
    }

    // MARK: - Actions (pass-through to the existing FilesController)

    @discardableResult
    func addURLs(_ urls: [URL]) -> Bool {
        filesController.add(urls)
    }

    func startAgain(optimizedOnly: Bool) {
        filesController.startAgainOptimized(optimizedOnly)
    }

    func stopSelected() {
        filesController.stopSelected()
    }

    func clearComplete() {
        filesController.clearComplete()
    }

    func revert() {
        filesController.revert()
    }

    func revealInFinder(_ rowsToReveal: [FileRowStore]) {
        let urls = rowsToReveal.map(\.jobProxy.filePath)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func delete(_ rowsToDelete: [FileRowStore]) {
        filesController.remove(contentsOf: rowsToDelete.map(\.jobProxy))
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        filesController.moveObjectsInArrangedObjects(from: source, to: UInt(destination))
    }

    var canClearComplete: Bool {
        filesController.canClearComplete
    }

    var canRevert: Bool {
        filesController.canRevert
    }
}
