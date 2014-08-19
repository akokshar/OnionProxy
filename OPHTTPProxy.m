//
//  OPHTTPProxy.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 04/08/14.
//
//

#import "OPHTTPProxy.h"
#import "OPStream.h"

@interface OPHTTPProxy() <NSStreamDelegate, OPStreamDelegate> {
    NSThread *proxyThread;
    CFHTTPMessageRef httpRequest;
}

@property (atomic) BOOL isRunning;
@property (retain) NSOutputStream *outputStream;
@property (retain) NSInputStream *inputStream;
@property (retain) OPStream *torStream;

/**
 * Start serving connection. OPHTTPProxy object is retained by inputStream and outputStream,
 * so caller can release it after this call is made.
 */
- (void) start;
- (void) doStart;
- (void) run;
- (void) doStop;
- (void) stop;

@end

@implementation OPHTTPProxy

- (void) start {
    [proxyThread start];
    [self performSelector:@selector(doStart) onThread:proxyThread withObject:NULL waitUntilDone:YES];
}

- (void) doStart {
    
}

- (void) run {
    [self logMsg:@"proxy thread started"];
    @autoreleasepool {
        self.isRunning = YES;

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

        self.inputStream.delegate = self;
        self.outputStream.delegate = self;

        [self.inputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        [self.outputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];

        [self.inputStream open];
        [self.outputStream open];

        while (self.isRunning && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);

        [self.inputStream close];
        [self.outputStream close];

        [self.inputStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        [self.outputStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];

        self.inputStream.delegate = NULL;
        self.outputStream.delegate = NULL;
    }
    [self logMsg:@"proxy thread finished"];
}

- (void) doStop {
    self.isRunning = NO;
}

- (void) stop {
    if (self.isRunning) {
        [self performSelector:@selector(doStop) onThread:proxyThread withObject:NULL waitUntilDone:YES];
    }
}

- (void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
    switch (streamEvent) {
        case NSStreamEventOpenCompleted: {

        } break;

        case NSStreamEventHasBytesAvailable: {
            uint8 buffer[1024];
            NSInteger len;

            while ([self.inputStream hasBytesAvailable]) {
                len = [self.inputStream read:buffer maxLength:sizeof(buffer)];
                if (len > 0) {
                    if (self.torStream) {
                        [self.torStream sendData:[NSData dataWithBytes:buffer length:len]];
                    }
                    else {
                        CFHTTPMessageAppendBytes(httpRequest, buffer, len);
                        if (CFHTTPMessageIsHeaderComplete(httpRequest) ) {
                            NSString *hostStr = (NSString *)CFHTTPMessageCopyHeaderFieldValue(httpRequest, (CFStringRef)@"Host");
                            NSArray *hostPort = [hostStr componentsSeparatedByString:@":"];
                            uint16 port = 80;
                            if ([hostPort count] == 2) {
                                port = [[hostPort objectAtIndex:1] shortValue];
                            }

                            self.torStream = [OPStream streamToPort:port forClient:self];
                            if (self.torStream) {
                                // reply with error to client
                            }
                            else {
                                NSData *httpReqData = (NSData *)CFHTTPMessageCopySerializedMessage(httpRequest);
                                [self.torStream sendData:httpReqData];
                                [httpReqData release];
                            }
                        }
                    }
                }
            }
            
        } break;

        case NSStreamEventHasSpaceAvailable: {

        } break;

        case NSStreamEventEndEncountered: {

        } break;

        case NSStreamEventErrorOccurred: {

        } break;

        case NSStreamEventNone: {

        } break;
    }
}

- (void) streamDidConnect:(OPStream *)stream {

}

- (void) streamDidDisconnect:(OPStream *)stream {

}

- (void) stream:(OPStream *)stream didReceiveData:(NSData *)data {

}

- (void) stream:(OPStream *)connection didFailWithError:(NSError *)error {

}

- (id) initWithInputStream:(NSInputStream *)inputStream andOutputStream:(NSOutputStream *)oututStream {
    [self logMsg:@"INIT HTTPPROXY"];
    self = [super init];
    if (self) {
        self.inputStream = inputStream;
        self.outputStream = oututStream;

        self.torStream = NULL;

        self.isRunning = NO;
        proxyThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
        httpRequest = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, YES);
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC HTTPPROXY"];

    CFRelease(httpRequest);
    [proxyThread release];

    self.inputStream = NULL;
    self.outputStream = NULL;

    self.torStream = NULL;

    [super dealloc];
}

+ (void) serveConnectionWithInputStream:(NSInputStream *)iStream andOutputStream:(NSOutputStream *)oStream {
    if (iStream == NULL && oStream == NULL) {
        return;
    }
    
    OPHTTPProxy *proxy = [[OPHTTPProxy alloc] initWithInputStream:iStream andOutputStream:oStream];
    [proxy start];
    [proxy release];
}

@end
