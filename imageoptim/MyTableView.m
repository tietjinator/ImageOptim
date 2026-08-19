#import "MyTableView.h"

@import Quartz;
@implementation MyTableView

- (BOOL)allowsVibrancy {
    return false;
}

- (void)quickLook {
    if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible]) {
        [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
    } else {
        [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
    }
}

@end
