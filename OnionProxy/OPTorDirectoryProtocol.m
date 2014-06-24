//
//  OPTorDirectoryProtocol.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 11/06/14.
//
//

#import "OPTorDirectoryProtocol.h"

@interface OPTorDirectoryProtocol() <NSURLConnectionDataDelegate> {

}

@property (retain) NSTimer *resourceTimeoutTimer;
@property (retain) NSURLConnection *connection;

- (void) startResourceTimer;
- (void) stopResourceTimer;
- (void) timerFireMethod:(NSTimer *)timer;

@end

@implementation OPTorDirectoryProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
//    static NSUInteger requestCount = 0;
//    NSLog(@"Request #%lu: URL = %@", (unsigned long)requestCount++, request.URL.absoluteString);

    if ([request.URL.scheme isEqualToString:@"opdir"]) {
        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void) startLoading {
    // TODO:
    // use TOR circuit if ready
    // otherwise the next

    NSMutableURLRequest *httpRequest = [self.request mutableCopy];
    NSString *httpURLStr = [@"http:" stringByAppendingString:self.request.URL.resourceSpecifier];
    httpRequest.URL = [NSURL URLWithString:httpURLStr];


    self.connection = [NSURLConnection connectionWithRequest:httpRequest delegate:self];
    [httpRequest release];

    [self startResourceTimer];
}

- (void) stopLoading {
    [self stopResourceTimer];

    [self.connection cancel];
    self.connection = NULL;
}

- (void) startResourceTimer {
    self.resourceTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.request.timeoutInterval
                                                                 target:self
                                                               selector:@selector(timerFireMethod:)
                                                               userInfo:NULL
                                                                repeats:NO];
}

- (void) stopResourceTimer {
    [self.resourceTimeoutTimer invalidate];
    self.resourceTimeoutTimer = NULL;
}

- (void) timerFireMethod:(NSTimer *)timer {
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:1001 userInfo:NULL]];

    [self.connection cancel];
    self.connection = NULL;

    self.resourceTimeoutTimer = NULL;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        [self stopResourceTimer];
    }
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self stopResourceTimer];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self stopResourceTimer];
    [self.client URLProtocol:self didFailWithError:error];
}

@end
