//
//  PreferencesTabSelection.swift
//  ImageOptim
//
//  Thin, @objc-visible bridge so PrefsController.m (Objective-C) can ask the SwiftUI
//  Preferences window to jump to the Quality tab, replacing the old
//  `[self.tabs selectTabViewItemAtIndex:1]` call in -showLossySettings:.
//

import Combine
import Foundation

enum PreferencesTab: Hashable {
    case general, quality, speed
}

@MainActor
@objc final class PreferencesTabSelection: NSObject, ObservableObject {
    @Published var selectedTab: PreferencesTab = .general

    @objc func selectQualityTab() {
        selectedTab = .quality
    }
}
