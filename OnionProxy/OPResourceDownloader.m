//
//  OPURLDownload.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 12/03/14.
//
//

#import "OPResourceDownloader.h"
#import "OPConsensus.h"
#import "OPTorNode.h"
#import "OPAuthorityServer.h"
#import "OPAuthority.h"
#import "OPJobDispatcher.h"


@interface OPResourceDownloader() {
//    NSURLDownload *urlDownload;
//    NSString *fileName;
//    NSConditionLock *wait;
}

@property (readonly, getter = getIsSuccessful) BOOL isSuccessful;

@end

@implementation OPResourceDownloader

@synthesize isSuccessful = _isSuccessful;

- (BOOL) getIsSuccessful {
//    [wait lockWhenCondition:1];
//    [wait unlock];
    
    return _isSuccessful;
}
- (id) initWithUrl:(NSURL *)url saveTo:(NSString *)file timeout:(NSUInteger)timeout {
    self = [super init];
    if (self) {
        
//        wait = [[NSConditionLock alloc] initWithCondition:0];
//        [wait lock];
        
        _isSuccessful = NO;

//        fileName = file;
//        [fileName retain];
        
        NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:5];
        NSURLResponse *response = NULL;
        NSError *error = NULL;
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        if (data) {
            _isSuccessful = YES;
            [data writeToFile:file atomically:NO];
            [self logMsg:@"Downloaded '%@'", url];
        }
        else {
            _isSuccessful = NO;
            [self logMsg:@"Download failed '%@'", url];
        }
        
        
//        urlDownload = [[NSURLDownload alloc] initWithRequest:request delegate:self];
////        [self logMsg:@"[[NSRunLoop currentRunLoop] run]"];
//        [[NSRunLoop currentRunLoop] run];
////        [self logMsg:@"init done"];
    }
    return self;
}

- (void) dealloc {
//    [fileName release];
////    [wait release];
//    [urlDownload release];
    
    [super dealloc];
}

//- (void) download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)fname {
//    [download setDestination:fileName allowOverwrite:YES];
//}
//
//- (void) downloadDidFinish:(NSURLDownload *)download {
//    _isSuccessful = YES;
//    [wait unlockWithCondition:1];
//    [self logMsg:@"download complete"];
//}
//
//- (void) download:(NSURLDownload *)download didFailWithError:(NSError *)error {
//    _isSuccessful = NO;
//    [wait unlockWithCondition:1];
//    [self logMsg:@"error while downloading"];
//}

+ (BOOL) downloadFromIp:(NSString *)ip port:(NSString *)port resource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%@%@", ip, port, resource]];
    OPResourceDownloader *download = [[OPResourceDownloader alloc] initWithUrl:url saveTo:file timeout:timeout];
    BOOL result = download.isSuccessful;
    [download release];
    return result;
}

+ (BOOL) downloadResource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout {
    OPTorNode *cacheServer = [OPConsensus consensus].randomV2DirNode;
    if (cacheServer) {
        return [OPResourceDownloader downloadFromIp:cacheServer.ip port:cacheServer.dirPort resource:resource to:file timeout:timeout];
    }
    else {
        return [OPResourceDownloader downloadFromAuthorityResource:resource to:file timeout:5];
    }
}

+ (BOOL) downloadFromAuthorityResource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout {
    OPAuthorityServer *authority = [OPAuthority authority].randomServer;
    return [OPResourceDownloader downloadFromIp:authority.ipAddress port:authority.dirPort resource:resource to:file timeout:timeout];
}

@end
