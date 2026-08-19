//
//  MainChromeViewFactory.swift
//  ImageOptim
//
//  Same reason as PreferencesWindowFactory: Objective-C can't instantiate a generic
//  NSHostingController<MainChromeView> directly, so this does it in Swift and hands back a
//  plain NSViewController.
//

import SwiftUI

@objc final class MainChromeViewFactory: NSObject {
    @objc @MainActor static func makeViewController(
        store: FileListStore,
        onAdd: @escaping () -> Void,
        onAgain: @escaping (Bool) -> Void,
        onSettings: @escaping () -> Void
    ) -> NSViewController {
        let controller = NSHostingController(
            rootView: MainChromeView(store: store, onAdd: onAdd, onAgain: onAgain, onSettings: onSettings)
        )
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        return controller
    }
}
