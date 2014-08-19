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

NSString * const kOPDirectoryProtocolContentEncodingKey = @"Content-Encoding";
NSString * const kOPDirectoryProtocolAcceptEncodingKey = @"Accept-Encoding";

@interface OPProtocol() <NSURLConnectionDataDelegate, OPStreamDelegate> {
}

@property (atomic) BOOL isResponseSent;
@property (assign, setter=setHttpResponse:, getter=getHttpResponse) CFHTTPMessageRef httpResponse;

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

@synthesize httpResponse = _httpResponse;

- (void) setHttpResponse:(CFHTTPMessageRef)newHttpResponse {
    @synchronized(self) {
        if (_httpResponse) {
            CFRelease(_httpResponse);
        }
        _httpResponse = newHttpResponse;
    }
}

- (CFHTTPMessageRef) getHttpResponse {
    @synchronized(self) {
        return _httpResponse;
    }
}

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
    self.isResponseSent = NO;
    self.httpResponse = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);

    if ([self.request.URL.scheme isEqualToString:@"opdir"]) {
        // if tor network available use it. otherwise fallback to direct connection
        self.torStream = [OPStream directoryStreamForClient:self];
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
        [self startResourceTimer];
    }
    else if ([self.request.URL.scheme hasPrefix:@"http"]) {
        // shoud never get here!
//        NSData *errorTemplate = [[NSData alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"httpError" ofType:@"txt"]];
//        [self didReceiveData:errorTemplate];
//        [self didFinishLoading];
//        [errorTemplate release];
    }
    else {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"OPProtocolDomain" code:1004 userInfo:NULL]];
    }
}

- (void) stopLoading {
    [self stopResourceTimer];

    [self.torStream close];
    self.torStream = NULL;

    [self.connection cancel];
    self.connection = NULL;

    self.httpResponse = NULL;
}

- (void) dealloc {
    [self stopResourceTimer];
    self.connection = NULL;

    [self.torStream close];
    self.torStream = NULL;

    self.httpResponse = NULL;

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

    if (self.connection) {
        [self.connection cancel];
        self.connection = NULL;
    }
    if (self.torStream) {
        [self.torStream close];
        self.torStream = NULL;
    }

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

- (void) streamDidConnect:(OPStream *)stream {
    //NSLog(@"streamDidConnect");
    NSURL *directoryResourceUrl = [NSURL URLWithString:[[self.request URL] path]];
    CFHTTPMessageRef httpRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (CFStringRef)[self.request HTTPMethod], (CFURLRef)directoryResourceUrl, kCFHTTPVersion1_1);

    for (NSString *header in [self.request allHTTPHeaderFields]) {
        CFHTTPMessageSetHeaderFieldValue(httpRequest, (CFStringRef)header, (CFStringRef)[[self.request allHTTPHeaderFields] objectForKey:header]);
    }
    CFHTTPMessageSetHeaderFieldValue(httpRequest, (CFStringRef)kOPDirectoryProtocolAcceptEncodingKey, (CFStringRef)@"deflate, gzip");
    CFHTTPMessageSetBody(httpRequest, (CFDataRef)[self.request HTTPBody]);

    NSData *httpRequestData = (NSData *) CFHTTPMessageCopySerializedMessage(httpRequest);

    //CFShow(httpRequest);

    [self.torStream sendData:httpRequestData];

    [httpRequestData release];
    CFRelease(httpRequest);
}

- (void) streamDidDisconnect:(OPStream *)stream {
    NSData *bodyData = (NSData *) CFHTTPMessageCopyBody(self.httpResponse);
    NSString * contentEncoding = (NSString *) CFHTTPMessageCopyHeaderFieldValue(self.httpResponse, (CFStringRef)kOPDirectoryProtocolContentEncodingKey);

    NSData *decompressedData = NULL;

    if (!contentEncoding || [contentEncoding isCaseInsensitiveLike:@"identity"]) {
        [self didReceiveData:bodyData];
        [self didFinishLoading];
    }

    else if ([contentEncoding isCaseInsensitiveLike:@"deflate"]) {
        SecTransformRef decodeTransform = SecDecodeTransformCreate(kSecZLibEncoding, NULL);
        if (decodeTransform) {
            SecTransformSetAttribute(decodeTransform, kSecTransformInputAttributeName, bodyData, NULL);
            decompressedData = SecTransformExecute(decodeTransform, NULL);
            CFRelease(decodeTransform);
        }
        else {
            [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"OPProtocolDomain" code:1003 userInfo:NULL]];
        }
    }

    else if ([contentEncoding isCaseInsensitiveLike:@"gzip"]) {
        //TODO: unpack gzip data
    }

    else {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"OPProtocolDomain" code:1002 userInfo:NULL]];
    }

    if (decompressedData) {
        [self didReceiveData:decompressedData];
        [self didFinishLoading];
        [decompressedData release];
    }

    [contentEncoding release];
    [bodyData release];
}

- (void) stream:(OPStream *)stream didReceiveData:(NSData *)data {
    //NSLog(@"streamDidReceiveData: %@", data);

    if ( !CFHTTPMessageAppendBytes(self.httpResponse, [data bytes], [data length]) ) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"OPProtocolDomain" code:1001 userInfo:NULL]];
        return;
    }

    if ((self.isResponseSent == NO) && (CFHTTPMessageIsHeaderComplete(self.httpResponse))) {
        NSUInteger statusCode =  CFHTTPMessageGetResponseStatusCode(self.httpResponse);
        NSString *httpVersion = (NSString *) CFHTTPMessageCopyVersion(self.httpResponse);
        NSDictionary *headerFields = (NSDictionary *) CFHTTPMessageCopyAllHeaderFields(self.httpResponse);
        NSMutableDictionary *fixedHeaderFields = [[NSMutableDictionary alloc] initWithDictionary:headerFields];
        [fixedHeaderFields removeObjectForKey:kOPDirectoryProtocolContentEncodingKey];

        NSHTTPURLResponse *urlResponse = [[NSHTTPURLResponse alloc] initWithURL:[self.request URL] statusCode:statusCode HTTPVersion:httpVersion headerFields:fixedHeaderFields];
        [httpVersion release];
        [headerFields release];
        [fixedHeaderFields release];

        [self didReceiveResponse:urlResponse];

        [urlResponse autorelease];
        self.isResponseSent = YES;
    }

    //TODO: check contentLenght. Might be not necessary.
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
