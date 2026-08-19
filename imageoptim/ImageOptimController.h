/* ImageOptim */
#import <Quartz/Quartz.h>

extern NSDictionary *statusImages;

@class FilesController;
@class PrefsController;

@interface ImageOptimController : NSObject<NSApplicationDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate> {
    IBOutlet NSTableView *tableView;
    IBOutlet FilesController *__unsafe_unretained filesController;

    PrefsController *prefsController;

    IBOutlet NSTextField *statusBarLabel;
    IBOutlet NSTextView *credits;

    // Bottom control strip, replaced at runtime (in -awakeFromNib) with a SwiftUI
    // MainChromeView hosted over this same region — see ImageOptimController.m and
    // SwiftUI/MainChromeView.swift. These AppKit controls stay in the xib, hidden, so the
    // rest of the window (menus, table, drag-and-drop) is untouched by this migration step.
    IBOutlet NSButton *addButton;
    IBOutlet NSProgressIndicator *chromeProgressIndicator;
    IBOutlet NSButton *againButton;
    IBOutlet NSButton *settingsButton;

    // File list area, same runtime-swap approach: FadeView (id "XNq-qc-Ci6" in the xib) and
    // tableView's enclosing NSScrollView are hidden in -installSwiftFileList, replaced with a
    // SwiftUI FileListView hosted in the same region. See SwiftUI/FileListView.swift.
    IBOutlet NSView *fadeView;

    IBOutlet NSTableColumn *fileColumn, *sizeColumn, *originalSizeColumn, *savingsColumn, *bestToolColumn;

    QLPreviewPanel *previewPanel;

    dispatch_source_t statusBarUpdateQueue;
    IBOutlet NSNumberFormatter *savingsFormatter;
}

- (IBAction)showPrefs:(id)sender;
- (IBAction)showLossyPrefs:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)startAgain:(id)sender;
- (IBAction)startAgainOptimized:(id)sender;
- (IBAction)clearComplete:(id)sender;

- (IBAction)quickLookAction:(id)sender;
- (IBAction)openHomepage:(id)sender;
- (IBAction)viewSource:(id)sender;
- (IBAction)openDonationPage:(id)sender;
- (IBAction)browseForFiles:(id)sender;

@property (readonly) int numberOfCPUs;
- (void)loadCreditsHTML:(id)_;

@property (unsafe_unretained, readonly) FilesController *filesController;
@end
