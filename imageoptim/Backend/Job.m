//
//  Created by porneL on 8.wrz.07.
//

#import "Job.h"
#import "TempFile.h"
#import "ImageOptimController.h"
#import "Workers/Save.h"
#import "Workers/AdvCompWorker.h"
#import "Workers/PngquantWorker.h"
#import "Workers/PngoutWorker.h"
#import "Workers/OxiPngWorker.h"
#import "Workers/PngCrushWorker.h"
#import "Workers/ZopfliWorker.h"
#import "Workers/JpegoptimWorker.h"
#import "Workers/JpegtranWorker.h"
#import "Workers/GifsicleWorker.h"
#import "Workers/SvgoWorker.h"
#import "Workers/SvgcleanerWorker.h"
#import "Workers/GuetzliWorker.h"
#import "Workers/HeicToJpegWorker.h"
#import <sys/xattr.h>
#import "log.h"
#include "ResultsDb.h"
#include <CommonCrypto/CommonDigest.h>

@interface ToolStats : NSObject {
@public
    NSString *name;
    NSUInteger fileSize;
    double ratio;
}
@end

@implementation ToolStats
- (instancetype)initWithName:(NSString *)aName oldSize:(NSUInteger)oldSize newSize:(NSUInteger)size {
    if ((self = [super init])) {
        name = aName;
        fileSize = size;
        ratio = (double)oldSize / (double)size;
    }
    return self;
}
@end

@interface Job ()
@property (assign) BOOL isDone;
@property (assign) BOOL isFailed;
@property (readwrite, nullable) File *initialInput, *unoptimizedInput, *wipInput, *savedOutput, *revertFile;
@end

@implementation Job {
    BOOL preservePermissions;
    BOOL preserveDates;
    BOOL preserveOriginal;
    NSString *filenamePrefix;
    NSString *filenameSuffix;
    NSString *outputFolderPath;
}

@synthesize workersPreviousResults, filePath, displayName, statusText, statusOrder, statusImageName, bestToolName, isFailed, isDone;

- (instancetype)initWithFilePath:(nonnull NSURL *)aPath resultsDatabase:(nullable ResultsDb *)aDb {
    if (self = [self init]) {
        workersPreviousResults = [NSMutableDictionary new];
        bestTools = [NSMutableDictionary new];
        filePath = aPath;
        db = aDb;
        self.displayName = [[NSFileManager defaultManager] displayNameAtPath:filePath.path];
        [self setStatus:@"wait" order:0 text:NSLocalizedString(@"Waiting to be optimized", @"tooltip")];
    }
    return self;
}

- (nonnull NSString *)fileName {
    if (displayName) return displayName;
    return [filePath lastPathComponent];
}

- (nullable File *)optimizedFileWithFallback:(BOOL)fallback {
    File *optimizedFile = self.wipInput;
    if (optimizedFile) {
        return optimizedFile;
    }
    optimizedFile = self.savedOutput;
    if (optimizedFile) {
        return optimizedFile;
    }
    if (fallback) {
        return self.unoptimizedInput;
    } else {
        return nil;
    }
}

- (NSNumber *)percentOptimized {
    File *optimizedFile = self.wipInput;
    if (optimizedFile == self.unoptimizedInput && !self.savedOutput) {
        return nil; // early work in progress, don't display anything
    }

    optimizedFile = [self optimizedFileWithFallback:false];
    if (!optimizedFile && self.isDone && !self.isFailed) {
        return [NSNumber numberWithInteger:0];
    }

    NSUInteger byteSizeOptimized = [self optimizedFileWithFallback:false].byteSize;
    NSUInteger byteSizeOriginal = self.initialInput.byteSize;

    if (!byteSizeOptimized) {
        return nil;
    }
    double p = 100.0 - 100.0 * (double)byteSizeOptimized / (double)byteSizeOriginal;
    if (p < 0) return [NSNumber numberWithInteger:0];
    return [NSNumber numberWithDouble:p];
}

- (BOOL)isOptimized {
    File *unoptimizedInput = self.unoptimizedInput;
    File *optimizedFile = [self optimizedFileWithFallback:false];

    if (!optimizedFile || unoptimizedInput == optimizedFile) {
        return NO;
    }

    // A file-type conversion (HEIC -> JPEG) always counts as worth saving, even though the
    // re-encoded JPEG is typically *larger* than the source HEIC — HEVC-based HEIC is more
    // space-efficient than JPEG at equivalent quality, so gating on byte size here would
    // silently discard every successful conversion.
    if (optimizedFile->fileType != unoptimizedInput->fileType) {
        return YES;
    }

    return optimizedFile.byteSize < unoptimizedInput.byteSize;
}

- (NSNumber *)byteSizeOptimized {
    File *input = [self optimizedFileWithFallback:true];

    return [NSNumber numberWithUnsignedInteger:input.byteSize];
}

- (NSNumber *)byteSizeOriginal {
    File *input = self.initialInput;
    if (!input) {
        return nil;
    }
    return [NSNumber numberWithUnsignedInteger:input.byteSize];
}

- (void)updateBestToolName:(ToolStats *)newTool {
    bestTools[newTool->name] = newTool;

    NSString *smallestFileToolName = nil;
    NSUInteger smallestFile = self.unoptimizedInput.byteSize;
    NSString *bestRatioToolName = nil; float bestRatio = 0;
    for (NSString *name in bestTools) {
        ToolStats *t = bestTools[name];
        if (t->ratio > bestRatio) {bestRatioToolName = name; bestRatio = t->ratio;}
        if (t->fileSize < smallestFile) {smallestFileToolName = name; smallestFile = t->fileSize;}
    }
    NSString *newBestToolName;
    if (smallestFileToolName && bestRatioToolName && ![bestRatioToolName isEqualToString:smallestFileToolName]) {
        newBestToolName = [NSString stringWithFormat:NSLocalizedString(@"%@+%@", "toolname+toolname in Best Tool column"), bestRatioToolName, smallestFileToolName];
    } else {
        newBestToolName = smallestFileToolName ? smallestFileToolName : bestRatioToolName;
    }
    if (![newBestToolName isEqualToString:self.bestToolName]) {
        self.bestToolName = newBestToolName;
    }
}

- (void)setNewFileInitial:(nullable File *)initial {
    @synchronized(self) {
        [self willChangeValueForKey:@"byteSizeOriginal"];
        self.initialInput = initial;
        self.unoptimizedInput = initial;
        self.revertFile = nil;
        self.savedOutput = nil;
        self.bestToolName = nil;
        [self didChangeValueForKey:@"byteSizeOriginal"];
        lossyConverted = NO;
        [bestTools removeAllObjects];
    }
    [self setFileOptimized:initial];
}

- (void)setFileOptimized:(nullable File *)newFile {
    [self willChangeValueForKey:@"byteSizeOptimized"];
    [self willChangeValueForKey:@"percentOptimized"];
    self.wipInput = newFile;
    [self didChangeValueForKey:@"percentOptimized"];
    [self didChangeValueForKey:@"byteSizeOptimized"];
}

- (BOOL)setFileOptimized:(TempFile *)newFile toolName:(NSString *)toolname {
    if (!newFile) {
        return NO;
    }

    NSUInteger newSize = newFile.byteSize;
    BOOL changed = NO;
    @synchronized(self) {
        File *oldFile = self.wipInput;
        NSUInteger oldSize = oldFile.byteSize;

        BOOL isSmaller = newSize && newSize < oldSize;
        IODebug("%@ %@ file %@ from %lu to %lu in %@",
                toolname,
                isSmaller ? @"optimized" : @"did not optimize",
                _unoptimizedInput.path.path,
                (unsigned long)oldSize, (unsigned long)newSize,
                newFile.path.path);
        if (isSmaller) {
            [self setFileOptimized:newFile];
            [self performSelectorOnMainThread:@selector(updateBestToolName:) withObject:[[ToolStats alloc] initWithName:toolname oldSize:oldSize newSize:newSize] waitUntilDone:NO];
            changed = YES;
        }
    }
    return changed;
}

// Like setFileOptimized:toolName:, but always accepts the new file regardless of size —
// for workers that change the file's type (HEIC -> JPEG) rather than compress it. Gating on
// "is the result smaller" would silently discard every successful conversion, since a
// near-lossless JPEG re-encode of a HEIC photo is typically *larger* than the HEVC-based
// HEIC source.
- (BOOL)setFileConverted:(TempFile *)newFile toolName:(NSString *)toolname {
    if (!newFile) {
        return NO;
    }

    @synchronized(self) {
        File *oldFile = self.wipInput;
        NSUInteger oldSize = oldFile.byteSize;
        NSUInteger newSize = newFile.byteSize;
        IODebug("%@ converted file %@ from %lu to %lu in %@",
                toolname, _unoptimizedInput.path.path,
                (unsigned long)oldSize, (unsigned long)newSize,
                newFile.path.path);
        [self setFileOptimized:newFile];
        [self performSelectorOnMainThread:@selector(updateBestToolName:) withObject:[[ToolStats alloc] initWithName:toolname oldSize:oldSize newSize:newSize] waitUntilDone:NO];
    }
    return YES;
}

-(BOOL)removeExtendedAttrAtURL:(NSURL *)path
{
    NSDictionary *extAttrToRemove = @{ @"com.apple.FinderInfo"  : @1,
                                       @"com.apple.ResourceFork": @1,
                                       @"com.apple.quarantine"  : @1,
                                       @"com.apple.metadata:kMDItemWhereFroms": @1,
                                    };

    const char *fileSystemPath = [path.path fileSystemRepresentation];

    // call with NULL for the char *namebuf param first
    // in this case the method returns the size of the attributes buffer
    ssize_t size = listxattr(fileSystemPath, NULL, 0, 0);

    if (size <= 0) {
        return YES; // no attributes to remove
    }

    char nameBuf[size];
    memset(nameBuf, 0, size);

    size = listxattr(fileSystemPath, nameBuf, size, 0);
    if (size <= 0) {
        return NO; // failed to read promised attrs
    }

    int i = 0;
    while (i < size) {
        char *utf8name = &nameBuf[i];
        i += strlen(utf8name) + 1; // attrs are 0-terminated one after another

        NSString *name = @(utf8name);
        if (extAttrToRemove[name]) {
            if (removexattr(fileSystemPath, utf8name, 0) == 0) {
                IODebug("Removed %s from %@", utf8name, path.path);
            } else {
                IOWarn("Can't remove %s from %@", utf8name, path.path);
                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)trashFileAtURL:(NSURL *)path resultingItemURL:(NSURL **)returning error:(NSError **)err {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (returning) *returning = nil;

    if ([fm trashItemAtURL:path resultingItemURL:returning error:err]) {
        return YES;
    }
    IOWarn("Recovering trashing error %@", *err); // may fail on network drives
    sleep(1); // network drives lag?

    if (![fm fileExistsAtPath:path.path]) {
        // the file got deleted anyway?
        return YES;
    }

    NSURL *trashedPath = [[[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES] URLByAppendingPathComponent:@".Trash"] URLByAppendingPathComponent:[path lastPathComponent]];
    [fm removeItemAtURL:trashedPath error:nil];

    if ([fm moveItemAtURL:path toURL:trashedPath error:err]) {
        if (returning) *returning = trashedPath;
        return YES;
    }
    return NO;
}

- (BOOL)canRevert {
    return self.revertFile && self.isDone && !stopping;
}

- (BOOL)revert {
    if (![self canRevert]) {
        return NO;
    }
    [self cleanup];

    File *revertFile = self.revertFile;

    NSUInteger byteSizeOriginal = revertFile.byteSize;
    if (byteSizeOriginal != [File byteSize:revertFile.path]) {
        IOWarn(@"Revert path '%@' has wrong size, %ld expected", revertFile.path, (long)byteSizeOriginal);
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSURL *newFilePath = nil;
    if (![fm replaceItemAtURL:filePath withItemAtURL:revertFile.path backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:&newFilePath error:&err]) {
        IOWarn(@"Can't revert: %@ due to %@", revertFile.path, err);
        return NO;
    }

    if (newFilePath) {
        filePath = [newFilePath copy];
    }
    [filePath removeAllCachedResourceValues];
    [self setNewFileInitial:[self.revertFile copyOfPath:filePath]];
    [self setStatus:@"noopt" order:6 text:NSLocalizedString(@"Reverted to original", @"tooltip")];
    return YES;
}

// Expands {date} / {date:FORMAT} tokens in a prefix/suffix template against a single shared
// timestamp (passed in so a prefix and suffix used together always agree, rather than each
// grabbing its own -[NSDate date] microseconds apart). FORMAT is a plain NSDateFormatter
// pattern (e.g. "yy.MM.dd", "HH-mm-ss") — bare {date} defaults to "yy.MM.dd".
- (NSString *)expandDateTokensIn:(NSString *)template at:(NSDate *)now {
    if ([template rangeOfString:@"{date"].location == NSNotFound) {
        return template;
    }

    static NSRegularExpression *tokenRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{date(?::([^}]+))?\\}" options:0 error:nil];
    });

    NSMutableString *result = [template mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [tokenRegex matchesInString:template options:0 range:NSMakeRange(0, template.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSRange formatRange = [match rangeAtIndex:1];
        NSString *formatSpec = formatRange.location == NSNotFound ? @"yy.MM.dd" : [template substringWithRange:formatRange];

        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = formatSpec;
        NSString *formatted = [[formatter stringFromDate:now] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];

        [result replaceCharactersInRange:match.range withString:formatted];
    }
    return result;
}

// Where the optimized result should actually be written. Defaults to filePath itself
// (today's only behavior: overwrite in place) unless a prefix/suffix/output folder is
// configured, in which case it's a different file next to (or in) the configured location.
// When Preserve Original is on but none of those are set, falls back to an "-optimized"
// suffix rather than silently writing over the file it's meant to preserve.
//
// A HEIC source always gets a "jpg" extension here instead of filePath's own — which, by
// itself, is what makes saveResult treat it as a different-destination write (never
// overwriting/trashing the original .heic) without needing a separate special case there:
// once the extension differs, the "is this destination different from filePath" check below
// is true unconditionally, regardless of the other output settings.
- (NSURL *)computeDestinationURL {
    BOOL isHeicConversion = self.unoptimizedInput->fileType == FILETYPE_HEIC;
    NSString *ext = isHeicConversion ? @"jpg" : filePath.pathExtension;
    NSString *base = filePath.lastPathComponent.stringByDeletingPathExtension;

    NSDate *now = [NSDate date];
    NSString *prefix = [self expandDateTokensIn:(filenamePrefix ?: @"") at:now];
    NSString *suffix = [self expandDateTokensIn:(filenameSuffix ?: @"") at:now];
    BOOL noCustomFolder = outputFolderPath.length == 0;
    NSURL *destDir = noCustomFolder ? [filePath URLByDeletingLastPathComponent] : [NSURL fileURLWithPath:outputFolderPath isDirectory:YES];

    NSString *newName = [[prefix stringByAppendingString:base] stringByAppendingString:suffix];
    NSURL *destination = [[destDir URLByAppendingPathComponent:newName] URLByAppendingPathExtension:ext];

    // Preserve Original must never resolve to filePath itself -- not just when prefix/suffix/
    // output-folder are all left blank, but also e.g. if the user explicitly picked the
    // source's own folder as the "custom" output folder with no name change, which computes
    // the exact same destination through a different path. Checking the actual computed
    // collision (rather than which raw settings produced it) catches both.
    if (preserveOriginal && [destination isEqual:filePath]) {
        NSString *fallbackName = [[prefix stringByAppendingString:base] stringByAppendingString:@"-optimized"];
        destination = [[destDir URLByAppendingPathComponent:fallbackName] URLByAppendingPathExtension:ext];
    }

    return destination;
}

- (BOOL)saveResult {
    File *fileToSave = self.wipInput;
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *error = nil;

        // Writing somewhere other than filePath itself (prefix/suffix/output folder, or
        // Preserve Original's implicit "-optimized" fallback): the original is never trashed,
        // moved, or overwritten — just copy the optimized bytes to the computed destination
        // and leave everything about the source file untouched. No revert is tracked, since
        // there's nothing to revert: the original was never touched.
        NSURL *destination = [self computeDestinationURL];
        if (preserveOriginal || ![destination isEqual:filePath]) {
            NSURL *destEnclosingDir = [destination URLByDeletingLastPathComponent];
            if (![fm isWritableFileAtPath:destEnclosingDir.path]) {
                IOWarn("The output folder %@ is not writable", destEnclosingDir.path);
                return NO;
            }
            // Atomic replace, not delete-then-copy: if a previous output already exists at
            // this destination (e.g. a prior "Start Again") and the copy below fails partway
            // through (disk full, I/O error), deleting first would have already destroyed that
            // previous output with nothing to show for it. replaceItemAtURL: builds the
            // replacement before touching the existing item, so a failure leaves the original
            // destination content intact.
            NSURL *resultingURL = nil;
            if (![fm replaceItemAtURL:destination withItemAtURL:fileToSave.path backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:&resultingURL error:&error]) {
                IOWarn("Failed to write optimized file to %@: %@", destination.path, error);
                return NO;
            }
            if (resultingURL) {
                destination = resultingURL;
            }
            [destination removeAllCachedResourceValues];
            self.savedOutput = [fileToSave copyOfPath:destination size:fileToSave.byteSize];
            [self setFileOptimized:nil];
            return YES;
        }

        NSURL *moveFromPath = fileToSave.path;
        NSURL *enclosingDir = [filePath URLByDeletingLastPathComponent];

        // Dropbox is super buggy and actually loses files when they're moved/trashed quickly
        BOOL isDropboxFolder = [fm fileExistsAtPath:[enclosingDir URLByAppendingPathComponent:@".dropbox"].path] || [filePath.path containsString: @"/Dropbox/"];
        IOWarn("Detected path %@ is inside Dropbox. Will try to avoid Dropbox's bugs.", filePath);

        if (![fm isWritableFileAtPath:enclosingDir.path]) {
            IOWarn("The file %@ is in non-writeable directory %@", filePath.path, enclosingDir.path);
            return NO;
        }

        if (!isDropboxFolder && preservePermissions) {
            NSString *writeToFilename = [[NSString stringWithFormat:@".%@~imageoptim", [filePath.lastPathComponent stringByDeletingPathExtension]] stringByAppendingPathExtension:filePath.pathExtension];
            NSURL *writeToURL = [enclosingDir URLByAppendingPathComponent:writeToFilename];
            NSString *writeToPath = writeToURL.path;

            if ([fm fileExistsAtPath:writeToPath]) {
                if ([self trashFileAtURL:writeToURL resultingItemURL:nil error:&error]) {
                } else {
                    IOWarn("%@", error);
                    error = nil;
                    if (![fm removeItemAtURL:writeToURL error:&error]) {
                        IOWarn("%@", error);
                        return NO;
                    }
                }
            }

            // move destination to temporary location that will be overwritten
            if (![fm moveItemAtURL:filePath toURL:writeToURL error:&error]) {
                IOWarn("Can't move to %@ %@", writeToPath, error);
                return NO;
            }

            // copy original data for trashing under original file name
            if (![fm copyItemAtURL:writeToURL toURL:filePath error:&error]) {
                IOWarn("Can't write to %@ %@", filePath.path, error);
                return NO;
            }

            NSData *data = [NSData dataWithContentsOfURL:fileToSave.path];
            if (!data) {
                IOWarn("Unable to read %@", fileToSave.path);
                return NO;
            }

            if ([data length] != fileToSave.byteSize) {
                IOWarn("Temp file size %u does not match expected %u in %@ for %@", (unsigned int)[data length], (unsigned int)fileToSave.byteSize, fileToSave.path, filePath.path);
                return NO;
            }

            if ([data length] < 30) {
                IOWarn("File %@ is suspiciously small, could be truncated", fileToSave.path);
                return NO;
            }

            // overwrite old file that is under temporary name (so only content is replaced, not file metadata)
            NSFileHandle *writehandle = [NSFileHandle fileHandleForWritingToURL:writeToURL error:nil];
            if (!writehandle) {
                IOWarn("Unable to open %@ for writing. Check file permissions.", filePath.path);
                return NO;
            }

            [writehandle writeData:data]; // this throws on failure
            [writehandle truncateFileAtOffset:[data length]];
            [writehandle closeFile];

            moveFromPath = writeToURL;
        }

        if (preserveDates) {
            NSDictionary *originalAttributes = [fm attributesOfItemAtPath:filePath.path error:&error];
            if (error != NULL) {
                IOWarn("Can't get attributes for %@ %@", filePath.path, error);
                return NO;
            }

            NSDictionary *attributesToTransfer = [NSDictionary dictionaryWithObjectsAndKeys:[originalAttributes fileCreationDate], NSFileCreationDate, [originalAttributes fileModificationDate], NSFileModificationDate, NULL];
            [fm setAttributes:attributesToTransfer ofItemAtPath:moveFromPath.path error:&error];
            if (error != NULL) {
                IOWarn("Could not set creation and modification date for %@ %@", filePath.path, error);
                return NO;
            }
        }

        NSURL *revertPathTmp;
        if (!isDropboxFolder && [self trashFileAtURL:filePath resultingItemURL:&revertPathTmp error:&error]) {
            if (!self.revertFile) {
                File *previous = self.unoptimizedInput;
                self.revertFile = [previous copyOfPath:revertPathTmp size:previous.byteSize];
            }
        } else {
            IOWarn("Can't trash %@ %@", filePath.path, error);
            NSString *backupFileName = [[[filePath lastPathComponent] stringByAppendingString:@"~bak"] stringByAppendingPathExtension:[filePath pathExtension]];
            NSURL *backupPath = [enclosingDir URLByAppendingPathComponent:backupFileName];

            BOOL moved = [fm moveItemAtURL:filePath toURL:backupPath error:&error];
            if (!moved) {
                [fm removeItemAtURL:backupPath error:nil];
                moved = [fm moveItemAtURL:filePath toURL:backupPath error:&error];
            }

            if (moved) {
                if (isDropboxFolder) {
                    sleep(1); // give the buggy thing time to sync
                }
                NSURL *trashedPath = nil;
                if ([fm trashItemAtURL:backupPath resultingItemURL:&trashedPath error:nil]) {
                    backupPath = trashedPath;
                }

                if (!self.revertFile && backupPath) {
                    self.revertFile = [self.unoptimizedInput copyOfPath:backupPath];
                }
            } else {
                IOWarn("Can't move to %@ %@", backupPath, error);
                return NO;
            }
        }

        if (![fm moveItemAtURL:moveFromPath toURL:filePath error:&error]) {
            IOWarn("Failed to move from %@ to %@; %@", moveFromPath.path, filePath.path, error);
            return NO;
        }

        [filePath removeAllCachedResourceValues];
        self.savedOutput = [fileToSave copyOfPath:filePath size:fileToSave.byteSize];
        [self setFileOptimized:nil];
        if (isDropboxFolder) {
            sleep(1); // give the buggy thing time to sync
        }
        [self removeExtendedAttrAtURL:filePath];
    }
    @catch (NSException *e) {
        IOWarn("Exception thrown %@ while saving %@", e, filePath.path);
        return NO;
    }

    return YES;
}

- (void)setNooptStatus {
    [self setFileOptimized:nil]; // Needed to update 0% optimized display
    [self setStatus:@"noopt" order:5 text:NSLocalizedString(@"File cannot be optimized any further", @"tooltip")];
    self.isDone = YES;
    [self stopAllWorkers];
}

- (void)saveResultAndUpdateStatus {
    assert([self isBusy]);
    if ([self isOptimized]) {
        BOOL saved = [self saveResult];
        self.isDone = YES;
        [self stopAllWorkers];
        if (saved) {
            [self setStatus:@"ok" order:7 text:[NSString stringWithFormat:NSLocalizedString(@"Optimized successfully with %@", @"tooltip"), bestToolName]];
        } else {
            [self setError:NSLocalizedString(@"Optimized file could not be saved", @"tooltip")];
        }
    } else {
        [self setNooptStatus];
        if (!stopping && !self.isFailed) {
            [db setUnoptimizableFileHash:inputFileHash size:self.unoptimizedInput.byteSize];
        }
    }
}

- (void)enqueueWorkersInCPUQueue:(nonnull NSOperationQueue *)queue fileIOQueue:(nonnull NSOperationQueue *)aFileIOQueue serialQueue:(dispatch_queue_t)serialQueue defaults:(nonnull NSUserDefaults *)defaults {
    [self willChangeValueForKey:@"isBusy"];
    NSOperation *actualEnqueue = [NSBlockOperation blockOperationWithBlock:^{
        @synchronized(self) {
            [self doEnqueueWorkersInCPUQueue:queue serialQueue:serialQueue defaults:defaults];
        }
    }];
    @synchronized(self) {
        self.isDone = NO;
        self.isFailed = NO;
        stopping = NO;
        fileIOQueue = aFileIOQueue; // will be used for saving
        workers = [[NSMutableArray alloc] initWithCapacity:10];
        preservePermissions = [defaults boolForKey:@"PreservePermissions"];
        preserveDates = [defaults boolForKey:@"PreserveDates"];
        preserveOriginal = [defaults boolForKey:@"PreserveOriginal"];
        filenamePrefix = [defaults stringForKey:@"FilenamePrefix"] ?: @"";
        filenameSuffix = [defaults stringForKey:@"FilenameSuffix"] ?: @"";
        outputFolderPath = [defaults stringForKey:@"OutputFolderPath"] ?: @"";

        BOOL isQueueUnderUtilized = queue.operationCount < queue.maxConcurrentOperationCount;
        if (isQueueUnderUtilized) {
            actualEnqueue.queuePriority = NSOperationQueuePriorityVeryHigh;
        }

        [workers addObject:actualEnqueue];
        [fileIOQueue addOperation:actualEnqueue];
    }
    [self didChangeValueForKey:@"isBusy"];
}
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
- (void)setSettingsHash:(NSArray *)allWorkers {
    CC_MD5_CTX md5ctx = {};
    CC_MD5_Init(&md5ctx);
    CC_MD5_Update(&md5ctx, "3", 1); // to update when programs change
    for (Worker *w in allWorkers) {
        NSInteger tmp = [w settingsIdentifier];
        CC_MD5_Update(&md5ctx, &tmp, sizeof(tmp));
    }
    CC_MD5_Final((unsigned char *)settingsHash, &md5ctx);
}
#pragma GCC diagnostic pop

- (void)doEnqueueWorkersInCPUQueue:(nonnull NSOperationQueue *)queue serialQueue:(dispatch_queue_t)serialQueue defaults:(nonnull NSUserDefaults *)defs {
    [self setStatus:@"progress" order:3 text:NSLocalizedString(@"Inspecting file", @"tooltip")];

    NSError *err = nil;
    NSData *fileData = [NSData dataWithContentsOfURL:filePath options:NSDataReadingMappedIfSafe error:&err];
    NSUInteger length = [fileData length];

    File *input = [[File alloc] initWithData:fileData fromPath:filePath];

    if (!input || !length) {
        IOWarn(@"Can't open the file %@ %@", filePath.path, err);
        [self setNewFileInitial:nil];
        [self setError:NSLocalizedString(@"Can't open the file", @"tooltip, generic loading error")];
        return;
    }

    BOOL hasChangedSinceLastSave = self.savedOutput && self.savedOutput.byteSize != input.byteSize;
    BOOL hasBeenRunBefore = self.initialInput && !hasChangedSinceLastSave;

    // if file hasn't changed since last optimization, keep previous byteSizeOriginal, etc.
    if (!hasBeenRunBefore || hasChangedSinceLastSave) {
        [self setNewFileInitial:input];
    } else {
        self.unoptimizedInput = input;
        [self setFileOptimized:input];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    // Only require filePath itself to be writable when the job will actually overwrite it in
    // place. Preserve Original, a prefix/suffix, a different output folder, or HEIC conversion
    // all mean the source is never touched -- saveResult's own copy-branch checks the
    // destination's writability instead, so a read-only *source* shouldn't block those modes.
    BOOL willWriteInPlace = !preserveOriginal && [[self computeDestinationURL] isEqual:filePath];
    if (willWriteInPlace && ![fm isWritableFileAtPath:filePath.path]) {
        [self setError:NSLocalizedString(@"Optimized file could not be saved", @"tooltip")];
        return;
    }

    NSMutableArray *runFirst = [NSMutableArray new];
    NSMutableArray *runLater = [NSMutableArray new];

    NSMutableArray *worker_list = [NSMutableArray new];
    NSInteger level = [defs integerForKey:@"AdvPngLevel"]; // AdvPNG setting is reused for all tools now
    BOOL lossyEnabled = [defs boolForKey:@"LossyEnabled"];
    if (lossyEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [defs setBool:YES forKey:@"LossyUsed"];
        });
    }

    switch (input->fileType) {
    case FILETYPE_PNG:
        if (hasBeenRunBefore) {
            level++;
        }

        if (lossyEnabled) {
            NSInteger pngQuality = [defs integerForKey:@"PngMinQuality"];
            if (!lossyConverted && pngQuality < 100 && pngQuality > 30) {
                Worker *w = [[PngquantWorker alloc] initWithLevel:level minQuality:pngQuality file:self];
                [runFirst addObject:w];
                lossyConverted = YES;
            }
        }

        BOOL pngcrushEnabled = [defs boolForKey:@"PngCrush2Enabled"];
        BOOL oxipngEnabled = [defs boolForKey:@"OptiPngEnabled"];
        BOOL pngoutEnabled = [defs boolForKey:@"PngOutEnabled"];
        BOOL zopfliEnabled = [defs boolForKey:@"ZopfliEnabled"];
        BOOL advpngEnabled = [defs boolForKey:@"AdvPngEnabled"];
        BOOL removePNGChunks = [defs boolForKey:@"PngOutRemoveChunks"];

        if (level < 4 && zopfliEnabled) {
            pngoutEnabled = NO;
        }

        if (level < 2 && oxipngEnabled) {
            pngcrushEnabled = NO;
        }

        if (pngcrushEnabled) [worker_list addObject:[[PngCrushWorker alloc] initWithLevel:level defaults:defs file:self]];
        if (oxipngEnabled) [worker_list addObject:[[OxiPngWorker alloc] initWithLevel:level stripMetadata:removePNGChunks file:self]];
        if (pngoutEnabled) [worker_list addObject:[[PngoutWorker alloc] initWithLevel:level defaults:defs file:self]];
        if (advpngEnabled && removePNGChunks) {
            [worker_list addObject:[[AdvCompWorker alloc] initWithLevel:level file:self]];
        }
        if (zopfliEnabled) {
            ZopfliWorker *zw = [[ZopfliWorker alloc] initWithLevel:level defaults:defs file:self];
            zw.alternativeStrategy = hasBeenRunBefore;
            [worker_list addObject:zw];
        }
        break;
    case FILETYPE_JPEG:
        if (!lossyConverted && !hasBeenRunBefore && [defs boolForKey:@"GuetzliEnabled"] && [defs integerForKey:@"JpegOptimMaxQuality"] >= 80) {
            [worker_list addObject:[[GuetzliWorker alloc] initWithDefaults:defs serialQueue:serialQueue file:self]];
            lossyConverted = YES;
        }
        if ([defs boolForKey:@"JpegOptimEnabled"]) [worker_list addObject:[[JpegoptimWorker alloc] initWithDefaults:defs file:self]];
        if ([defs boolForKey:@"JpegTranEnabled"]) [worker_list addObject:[[JpegtranWorker alloc] initWithDefaults:defs file:self]];
        break;
    case FILETYPE_GIF:
        if ([defs boolForKey:@"GifsicleEnabled"]) {
            NSInteger gifQuality = [defs integerForKey:@"GifQuality"];
            if (lossyEnabled && !lossyConverted && gifQuality < 100 && gifQuality > 30) {
                Worker *w = [[GifsicleWorker alloc] initWithInterlace:NO quality:gifQuality file:self];
                [runFirst addObject:w];
                lossyConverted = YES;
            } else {
                [worker_list addObject:[[GifsicleWorker alloc] initWithInterlace:NO quality:100 file:self]];
                if (level > 1) {
                    [worker_list addObject:[[GifsicleWorker alloc] initWithInterlace:YES quality:100 file:self]];
                }
            }
        }
        break;
        case FILETYPE_SVG:
            if ([defs boolForKey:@"SvgoEnabled"]) {
                [worker_list addObject:[[SvgoWorker alloc] initWithLossy:lossyEnabled job:self]];
            }
            if ([defs boolForKey:@"SvgcleanerEnabled"]) {
                [worker_list addObject:[[SvgcleanerWorker alloc] initWithLossy:lossyEnabled job:self]];
            }
            break;
        case FILETYPE_HEIC: {
            if (![defs boolForKey:@"HeicToJpegEnabled"]) {
                [self setError:NSLocalizedString(@"HEIC conversion is disabled in Preferences", @"tooltip")];
                [self cleanup];
                return;
            }

            // Must run before any of the JPEG workers below — they operate on JPEG bytes that
            // don't exist until this one produces them. This is a *hard* precondition, unlike
            // Guetzli's relationship to Jpegoptim/Jpegtran in the plain FILETYPE_JPEG case
            // below (those work fine on a real JPEG whether or not Guetzli touched it first) —
            // so, unlike that case, worker_list order alone isn't enough: the runFirst/runLater
            // split further down is a scheduling *hint* (queue priority), not an ordering
            // guarantee, and gives no dependency at all between two workers that both land in
            // runLater (a common case for a single/small-batch drag-and-drop, since the queue
            // is underutilized). Explicit NSOperation dependencies below make this a hard
            // guarantee regardless of which bucket each worker ends up in.
            HeicToJpegWorker *heicWorker = [[HeicToJpegWorker alloc] initWithFile:self];
            [worker_list addObject:heicWorker];

            NSMutableArray<Worker *> *jpegWorkers = [NSMutableArray new];
            if (!lossyConverted && !hasBeenRunBefore && [defs boolForKey:@"GuetzliEnabled"] && [defs integerForKey:@"JpegOptimMaxQuality"] >= 80) {
                Worker *w = [[GuetzliWorker alloc] initWithDefaults:defs serialQueue:serialQueue file:self];
                [worker_list addObject:w];
                [jpegWorkers addObject:w];
                lossyConverted = YES;
            }
            if ([defs boolForKey:@"JpegOptimEnabled"]) {
                Worker *w = [[JpegoptimWorker alloc] initWithDefaults:defs file:self];
                [worker_list addObject:w];
                [jpegWorkers addObject:w];
            }
            if ([defs boolForKey:@"JpegTranEnabled"]) {
                Worker *w = [[JpegtranWorker alloc] initWithDefaults:defs file:self];
                [worker_list addObject:w];
                [jpegWorkers addObject:w];
            }
            for (Worker *w in jpegWorkers) {
                [w addDependency:heicWorker];
            }
            break;
        }
        default:
            [self setError:NSLocalizedString(@"File is neither PNG, GIF nor JPEG", @"tooltip")];
            [self cleanup];
            return;
    }

    BOOL isQueueUnderUtilized = queue.operationCount < queue.maxConcurrentOperationCount;

    for (Worker *w in worker_list) {
        // generally optimizers that have side effects should always be run first, one at a time
        // unfortunately that makes whole process single-core serial when there are very few files
        // so for small queues rely on nextOperation to give some order when possible
        if ([w makesNonOptimizingModifications]) {
            if (!isQueueUnderUtilized || [input isSmall]) {
                [runFirst addObject:w];
            } else {
                [w setQueuePriority:[runLater count] ? NSOperationQueuePriorityHigh : NSOperationQueuePriorityVeryHigh];
                [runLater addObject:w];
            }
        } else {
            [runLater addObject:w];
        }
    }

    // Create a hash that includes all optimization settings to invalidate file caches on settings changes
    [self setSettingsHash:[runFirst arrayByAddingObjectsFromArray:runLater]];

    // Can't check only file size, because then hash won't be available on save! if ([db hasResultWithFileSize:byteSizeOnDisk]) {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5_CTX md5ctx = {}, *md5ctxp = &md5ctx;
    CC_MD5_Init(md5ctxp);
    CC_MD5_Update(md5ctxp, settingsHash, 16);
    CC_MD5_Update(md5ctxp, [fileData bytes], (CC_LONG)[fileData length]);
    CC_MD5_Final((unsigned char *)inputFileHash, md5ctxp);
    if ([db getResultWithHash:inputFileHash]) { // FIXME: check for lossy
        NSLog(@"Skipping %@, because it has been optimized before", filePath.path);
        [self setNooptStatus];
        return;
    }
#pragma GCC diagnostic pop
    NSOperation *saveOp = [[Save alloc] initWithTarget:self selector:@selector(saveResultAndUpdateStatus) object:nil];

    Worker *previousWorker = nil;
    for (Worker *w in runFirst) {
        if (previousWorker) {
            [w addDependency:previousWorker];
            previousWorker.nextOperation = w;
        } else if ([input isSmall]) {
            [w setQueuePriority:NSOperationQueuePriorityVeryLow];
        } else if (![input isLarge]) {
            [w setQueuePriority:NSOperationQueuePriorityLow];
        }
        [saveOp addDependency:w];
        [queue addOperation:w];
        previousWorker = w;
    }

    Worker *runFirstDependency = previousWorker;
    for (Worker *w in runLater) {
        if (runFirstDependency) {
            [w addDependency:runFirstDependency];
        }
        if (previousWorker) {
            previousWorker.nextOperation = w;
        }
        [saveOp addDependency:w];
        [queue addOperation:w];
        previousWorker = w;
    }

    [self willChangeValueForKey:@"isBusy"];
    [workers addObjectsFromArray:runFirst];
    [workers addObjectsFromArray:runLater];
    [self didChangeValueForKey:@"isBusy"];

    if (![workers count]) {
        self.isDone = YES;
        [self setError:NSLocalizedString(@"All neccessary tools have been disabled in Preferences", @"tooltip")];
        [self cleanup];
    } else {
        [self updateStatusOfWorker:nil running:NO];
        [workers addObject:saveOp];
        [fileIOQueue addOperation:saveOp];
    }
}

- (void)stopAllWorkers {
    @synchronized(self) {
        [self willChangeValueForKey:@"isBusy"];
        [workers makeObjectsPerformSelector:@selector(cancel)];
        [workers removeAllObjects];
        [self didChangeValueForKey:@"isBusy"];
        stopping = NO;
    }
}

- (void)cleanup {
    [self stopAllWorkers];
    [self setFileOptimized:nil];
}

- (BOOL)isBusy {
    return [workers count] > 0;
}

- (BOOL)stop {
    if (![self isStoppable]) {
        return NO;
    }
    @synchronized(self) {
        if (!self.isDone) {
            stopping = YES;
            [self willChangeValueForKey:@"isBusy"];
            for (Worker *w in workers) {
                if (![w isKindOfClass:[Save class]]) {
                    [w cancel];
                }
            }
            [self didChangeValueForKey:@"isBusy"];
        }
    }
    return YES;
}

- (BOOL)isStoppable {
    return stopping || (!self.isDone && [self isBusy]);
}

- (void)updateStatusOfWorker:(nullable Worker *)currentWorker running:(BOOL)started {
    NSOperation *running = nil;

    [self willChangeValueForKey:@"isBusy"];
    @synchronized(self) {
        if (currentWorker && started) {
            running = currentWorker;
        } else {
            // technically I should pause all queues before that loop, but I'm going to allow some false "wait" icons instead
            for (NSOperation *op in workers) {
                // worker sets started:NO when it's ending, but isExecuting still shows true for it
                // Worker class is limited to user-visible workers (there are other for enqueuing, saving, etc.)
                if (op != currentWorker && [op isExecuting] && [op isKindOfClass:[Worker class]]) {
                    running = op;
                    break;
                }
            }
        }
    }
    [self didChangeValueForKey:@"isBusy"];

    if (running) {
        NSString *name = [[running className] stringByReplacingOccurrencesOfString:@"Worker" withString:@""];
        [self setStatus:@"progress" order:4 text:[NSString stringWithFormat:NSLocalizedString(@"Started %@", @"command name, tooltip"), name]];
    } else {
        [self setStatus:@"wait" order:1 text:NSLocalizedString(@"Waiting to be optimized", @"tooltip")];
    }
}

- (void)setError:(nonnull NSString *)text {
    self.isFailed = YES;
    [self setStatus:@"err" order:9 text:text];
}

- (void)setStatus:(nonnull NSString *)imageName order:(NSInteger)order text:(nonnull NSString *)text {
    // Keep failed status visible instead of replacing with progress/noopt/etc
    if (self.isFailed && ![imageName isEqualToString:@"ok"] && ![imageName isEqualToString:@"err"]) {
        return;
    }

    self->statusOrder = order;
    self.statusText = text;
    self.statusImageName = imageName;
}

- (nonnull NSString *)description {
    return [NSString stringWithFormat:@"%@ %ld/%ld/%ld (workers %ld) s=%d d=%d/%d %@", self.filePath,
            [self.byteSizeOriginal longValue],(long)self.wipInput.byteSize,(long)self.savedOutput.byteSize,
            [workers count], stopping, isDone, isFailed, self.statusText];
}

#pragma mark QL

- (NSURL *)previewItemURL {
    return [self optimizedFileWithFallback:true].path;
}

- (NSString *)previewItemTitle {
    return displayName;
}

@end
