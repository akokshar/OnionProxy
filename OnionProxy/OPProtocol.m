//
//  OPTorDirectoryProtocol.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 11/06/14.
//
//

#import "OPProtocol.h"
#import "OPTorNetwork.h"
#import "OPStream.h"

NSString * const kOPProtocolIsDirectoryRequest = @"IsDirectoryRequest";

@interface OPProtocol() <NSURLConnectionDataDelegate, OPHTTPStreamDelegate> {

}

@property (retain) NSTimer *resourceTimeoutTimer;
@property (retain) NSURLConnection *connection;
@property (retain) OPStream *torStream;

- (void) startResourceTimer;
- (void) stopResourceTimer;
- (void) timerFireMethod:(NSTimer *)timer;

- (void) didReceiveResponse:(NSURLResponse *)response;
- (void) didReceiveData:(NSData *)data;
- (void) didFinishLoading;
- (void) didFailWithError:(NSError *)error;

@end

@implementation OPProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {

    if ([NSURLProtocol propertyForKey:kOPProtocolIsDirectoryRequest inRequest:request]) {
        return NO;
    }

//    static NSUInteger requestCount = 0;
//    NSLog(@"Request #%lu: URL = %@", (unsigned long)requestCount++, request.description);

//    if ([request.URL.scheme isEqualToString:@"opdir"]) {
//        return YES;
//    }

    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void) startLoading {
    if ([self.request.URL.scheme hasPrefix:@"http"]) {

    }
    else if ([self.request.URL.scheme isEqualToString:@"opdir"]) {
        // if tor network available use it. otherwise fallback to direct connection
        self.torStream = [OPStream streamForClient:self withDirectoryResourceRequest:self.request];
        if (self.torStream) {
//            NSLog(@"===== Circuit is READY ====");
            [self.torStream open];
        }
        else {
//            NSLog(@"===== Circuit is NOT ready fallback to HTTP ====");

            NSMutableURLRequest *httpRequest = [self.request mutableCopy];
            NSString *httpURLStr = [@"http:" stringByAppendingString:self.request.URL.resourceSpecifier];
            httpRequest.URL = [NSURL URLWithString:httpURLStr];

            [NSURLProtocol setProperty:@YES forKey:kOPProtocolIsDirectoryRequest inRequest:httpRequest];
            self.connection = [NSURLConnection connectionWithRequest:httpRequest delegate:self];
            [httpRequest release];
        }
    }
    else {
        
    }

    [self startResourceTimer];
}

- (void) stopLoading {
    [self stopResourceTimer];

    [self.torStream close];
    self.torStream = NULL;

    [self.connection cancel];
    self.connection = NULL;
}

- (void) dealloc {
    [self stopResourceTimer];
    self.connection = NULL;

    [self.torStream close];
    self.torStream = NULL;

    [super dealloc];
}

#pragma mark -
#pragma mark Implementation

- (void) startResourceTimer {
//    self.resourceTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.request.timeoutInterval
//                                                                 target:self
//                                                               selector:@selector(timerFireMethod:)
//                                                               userInfo:NULL
//                                                                repeats:NO];
}

- (void) stopResourceTimer {
//    [self.resourceTimeoutTimer invalidate];
//    self.resourceTimeoutTimer = NULL;
}

- (void) timerFireMethod:(NSTimer *)timer {
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:1001 userInfo:NULL]];

    [self.connection cancel];
    self.connection = NULL;

    self.resourceTimeoutTimer = NULL;
}

- (void) didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        [self stopResourceTimer];
    }
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void) didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}

- (void) didFinishLoading {
    [self stopResourceTimer];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void) didFailWithError:(NSError *)error {
    [self stopResourceTimer];
    [self.client URLProtocol:self didFailWithError:error];
}

#pragma mark -
#pragma mark OPHTTPStream delegate

- (void) stream:(OPStream *)stream didReceiveResponse:(NSURLResponse *)response {
    //NSLog(@"streamDidReceiveResponse: %@", response);
    [self didReceiveResponse:response];
}

- (void) stream:(OPStream *)stream didReceiveData:(NSData *)data {
    //NSLog(@"streamDidReceiveData: %@", data);
    [self didReceiveData:data];
}

- (void) streamDidFinishLoading:(OPStream *)stream {
    [self didFinishLoading];
}

- (void) stream:(OPStream *)connection didFailWithError:(NSError *)error {
    [self didFailWithError:error];
}

#pragma mark -
#pragma mark URLConnection delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    //NSLog(@"connectionDidReceiveResponse: %@", response);
    [self didReceiveResponse:response];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    //    NSLog(@"connectionDidReceiveData: %@", data);
    [self didReceiveData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self didFinishLoading];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self didFailWithError:error];
}

@end
