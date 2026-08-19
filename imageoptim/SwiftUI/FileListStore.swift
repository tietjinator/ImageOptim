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

import Combine
import Foundation

// File-scope (not a type member) so it's usable from FileListStore's nonisolated deinit
// without tripping Swift 6's MainActor-isolation-of-static-members rule.
private let observedKeyPaths = ["arrangedObjects", "isBusy", "isStoppable"]

@MainActor
final class FileListStore: NSObject, ObservableObject {
    private let filesController: FilesController
    private var isObserving = false

    @Published private(set) var rows: [JobProxy] = []
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var isStoppable: Bool = false

    init(filesController: FilesController) {
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
                self.rows = (self.filesController.arrangedObjects as? [JobProxy]) ?? []
            case "isBusy":
                self.isBusy = self.filesController.isBusy
            case "isStoppable":
                self.isStoppable = self.filesController.isStoppable
            default:
                break
            }
        }
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

    var canClearComplete: Bool {
        filesController.canClearComplete
    }

    var canRevert: Bool {
        filesController.canRevert
    }
}
