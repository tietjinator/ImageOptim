//
//  PrefsController.m
//
//  Created by porneL on 24.wrz.07.
//  SwiftUI rewrite: builds its window in code and hosts PreferencesView (SwiftUI) instead of
//  loading Base.lproj/PrefsController.xib. All the behavior that used to live in this file's
//  KVO observer on NSUserDefaults (Guetzli slowness warning, Guetzli <-> JpegTranStripAll
//  cross-coupling) now lives in PreferencesView's .onChange handlers — see
//  SwiftUI/PreferencesView.swift.
//

#import "PrefsController.h"
#import "ImageOptimController.h"
#import "SwiftOptim-Swift.h"

@interface PrefsController ()
@property (nonatomic, strong) PreferencesTabSelection *tabSelection;
@end

@implementation PrefsController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 460)
                                                     styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    window.title = NSLocalizedString(@"ImageOptim Preferences", @"prefs window title");
    window.releasedWhenClosed = NO;

    if ((self = [super initWithWindow:window])) {
        _tabSelection = [PreferencesTabSelection new];
        window.contentViewController = [PreferencesWindowFactory makeViewControllerWithTabSelection:_tabSelection];
        [window center];
    }
    return self;
}

- (IBAction)showLossySettings:(id)sender {
    [self showWindow:sender];
    [self.tabSelection selectQualityTab];
}

- (IBAction)showHelp:(id)sender {
    [[self window] setHidesOnDeactivate:NO];

    NSString *locBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
    [[NSHelpManager sharedHelpManager] openHelpAnchor:@"main" inBook:locBookName];
}

@end
