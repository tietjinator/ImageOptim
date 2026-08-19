//
//  PreferencesWindowFactory.swift
//  ImageOptim
//
//  Objective-C can't directly instantiate NSHostingController<PreferencesView> — it's a
//  generic Swift class parameterized by a SwiftUI View, and Swift structs/View conformance
//  aren't bridgeable to ObjC at all. This factory does the generic instantiation in Swift and
//  hands PrefsController.m back a plain NSViewController, which is ObjC-visible.
//

import SwiftUI

@objc final class PreferencesWindowFactory: NSObject {
    @objc @MainActor static func makeViewController(tabSelection: PreferencesTabSelection) -> NSViewController {
        NSHostingController(rootView: PreferencesView(tabSelection: tabSelection))
    }
}
