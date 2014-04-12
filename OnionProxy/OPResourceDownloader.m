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
#import "OPConfig.h"
#import "OPAuthorityServer.h"
#import "OPAuthority.h"
#import "OPJobDispatcher.h"

@interface OPResourceDownloader() {
    NSThread *downloadThread;
    NSTimer *timeoutTimer;
    //NSURL *urlToDownload;
    NSURLDownload *urlDownload;
    NSConditionLock *wait;
}

@property (assign) NSUInteger timeout;
@property (retain) NSURLRequest *urlRequest;
@property (retain) NSString *fileName;

@property (assign) BOOL isSuccessful;
@property (assign) BOOL isDone;

- (void) startDownloadWaitUntilDone:(BOOL)needWait;
- (void) doStartDownload;
- (void) run;
- (void) timerFireMethod:(NSTimer *)timer;
- (void) doStopDownload;
- (void) stopDownload;

@end

@implementation OPResourceDownloader

@synthesize timeout = _timeout, urlRequest, fileName, isSuccessful, isDone;

- (void) startDownloadWaitUntilDone:(BOOL)needWait {
    @synchronized(self) {
        if (self.isDone) {
            return;
        }
        [downloadThread start];
        [self performSelector:@selector(doStartDownload) onThread:downloadThread withObject:NULL waitUntilDone:YES];
    }
    if (needWait) {
        [wait lock];
        [wait unlock];
    }
}

- (void) doStartDownload {
//    [self logMsg:@"download doStartDownload"];
    urlDownload = [[NSURLDownload alloc] initWithRequest:self.urlRequest delegate:self];
    [wait lock];
}

- (void) run {
//    static int i;
//    static int j;
//    [self logMsg:@"download thread Started %i", i++];
    
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.timeout target:self selector:@selector(timerFireMethod:) userInfo:NULL repeats:NO];
    [timeoutTimer setTolerance:3];
    
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    while (!self.isDone && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
    
    [pool release];
    
//    [self logMsg:@"download thread Finished %i", j++];
}

- (void) timerFireMethod:(NSTimer *)timer {
    [self logMsg:@"download timerFireMethod"];
    [self performSelector:@selector(doStopDownload) onThread:downloadThread withObject:NULL waitUntilDone:NO];
}

- (void) doStopDownload {
//    [self logMsg:@"download doStopDownload"];
    self.isDone = YES;
    [urlDownload release];
    [wait unlock];
}

- (void) stopDownload {
    @synchronized(self) {
        if (self.isDone) {
            return;
        }
        [self performSelector:@selector(doStopDownload) onThread:downloadThread withObject:NULL waitUntilDone:YES];
    }
}

- (void)downloadDidBegin:(NSURLDownload *)download {
    //    [self logMsg:@"download downloadDidBegin"];
}

- (void) download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)fname {
    //    [self logMsg:@"download set destination"];
    [download setDestination:self.fileName allowOverwrite:YES];
}

- (void) downloadDidFinish:(NSURLDownload *)download {
    self.isSuccessful = YES;
    [self stopDownload];
//    [self logMsg:@"download complete"];
}

- (void) download:(NSURLDownload *)download didFailWithError:(NSError *)error {
    self.isSuccessful = NO;
    [self stopDownload];
//    [self logMsg:@"error while downloading %@", self.urlRequest];
}

- (id) initWithUrl:(NSURL *)url saveTo:(NSString *)file timeout:(NSUInteger)timeout {
    self = [super init];
    if (self) {
        wait = [[NSConditionLock alloc] initWithCondition:0];
        downloadThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
        self.urlRequest = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:timeout];
        self.fileName = [NSString stringWithString:file];
        self.timeout = timeout + 1;
        
        urlDownload = NULL;
        
        self.isDone = NO;
        self.isSuccessful = NO;
    }
    return self;
}

- (void) dealloc {
    [self stopDownload];
    [downloadThread release];
    [wait release];
    self.urlRequest = NULL;
    self.fileName = NULL;
    
    [super dealloc];
}

+ (BOOL) downloadFromIp:(NSString *)ip port:(NSUInteger)port resource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%lu%@", ip, (unsigned long)port, resource]];
    OPResourceDownloader *download = [[OPResourceDownloader alloc] initWithUrl:url saveTo:file timeout:timeout];
    [download startDownloadWaitUntilDone:YES];
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
    NSUInteger serverIndex = arc4random() % [OPConfig config].serversCount;
    NSString *ip = [[OPConfig config] getIpAddrOfServerAtIndex:serverIndex];
    NSUInteger port = [[OPConfig config] getIpPortOfServerAtIndex:serverIndex];
    //OPAuthorityServer *authority = [OPAuthority authority].randomServer;
    return [OPResourceDownloader downloadFromIp:ip port:port resource:resource to:file timeout:timeout];
}

@end
