//
//  PreferencesTabSelection.swift
//  ImageOptim
//
//  Thin, @objc-visible bridge so PrefsController.m (Objective-C) can ask the SwiftUI
//  Preferences window to jump to the Quality pane, replacing the old
//  `[self.tabs selectTabViewItemAtIndex:1]` call in -showLossySettings:. The pane list itself
//  changed shape (sidebar-style, IINA-inspired — see PreferencesView.swift) but this ObjC-
//  facing surface didn't: -showLossySettings: still just calls -selectQualityTab.
//

import Combine
import Foundation

enum PreferencesTab: Hashable {
    case tools, metadata, files, performance, quality, speed
}

@MainActor
@objc final class PreferencesTabSelection: NSObject, ObservableObject {
    @Published var selectedTab: PreferencesTab = .tools

    @objc func selectQualityTab() {
        selectedTab = .quality
    }
}
