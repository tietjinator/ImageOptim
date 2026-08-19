//
//  HeicToJpegWorker.m
//  ImageOptim
//
//  Decodes a HEIC/HEIF source and re-encodes it as a near-lossless JPEG, which then flows
//  into the same JpegoptimWorker/JpegtranWorker/GuetzliWorker pipeline a native JPEG input
//  would (see Job.m's FILETYPE_HEIC dispatch case) — this worker's only job is the format
//  conversion itself, not the real compression.
//
//  No command-line tool involved, unlike every other Worker here — subclasses CommandWorker
//  anyway purely for its -run/-main orchestration (temp path handling, exception safety),
//  never touching its NSTask machinery.
//

#import "HeicToJpegWorker.h"
#import "../Job.h"
#import "../File.h"
#import "../TempFile.h"
#import "../../log.h"

@implementation HeicToJpegWorker

- (BOOL)makesNonOptimizingModifications {
    return YES;
}

- (BOOL)optimizeFile:(File *)file toTempPath:(NSURL *)temp {
    NSBitmapImageRep *inputRep = (NSBitmapImageRep *)[NSBitmapImageRep imageRepWithContentsOfURL:file.path];
    if (!inputRep) {
        IOWarn("Could not decode HEIC file %@", file.path);
        return NO;
    }

    NSData *jpegData = [inputRep representationUsingType:NSBitmapImageFileTypeJPEG
                                                properties:@{NSImageCompressionFactor: @(1.0)}];
    if (!jpegData || ![jpegData writeToURL:temp atomically:NO]) {
        IOWarn("Could not encode JPEG for %@", file.path);
        return NO;
    }

    // Not [file tempCopyOfPath:temp], which inherits fileType from the input (still HEIC
    // here) — the whole point of this worker is changing the type, not preserving it.
    TempFile *output = [[TempFile alloc] initWithType:FILETYPE_JPEG size:jpegData.length fromPath:temp];

    return [job setFileConverted:output toolName:@"HEIC"];
}

@end
