//
//  FileListViewFactory.swift
//  ImageOptim
//
//  Same reason as PreferencesWindowFactory/MainChromeViewFactory: Objective-C can't
//  instantiate a generic NSHostingController<FileListView> directly.
//

import SwiftUI

@objc final class FileListViewFactory: NSObject {
    @objc @MainActor static func makeViewController(store: FileListStore) -> NSViewController {
        let controller = NSHostingController(rootView: FileListView(store: store))
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        return controller
    }
}
