//
//  PrefsController.h
//
//  Created by porneL on 24.wrz.07.
//  SwiftUI rewrite: window content is now PreferencesView (SwiftUI/PreferencesView.swift),
//  built programmatically instead of loaded from Base.lproj/PrefsController.xib.
//

@import Cocoa;
@class ImageOptimController;

@interface PrefsController : NSWindowController

- (IBAction)showHelp:(id)sender;
- (IBAction)showLossySettings:(id)sender;
@end
