//
//  OPListener.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 30/07/14.
//
//

#import "OPListener.h"

#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface OPListener() {
    NSThread *listenThread;
    CFRunLoopSourceRef runLoopSource;
}

@property (retain) id<OPListenerDelegate>delegate;
@property (assign, setter=setSocketRef:,getter=getSocketRef) CFSocketRef socketRef;
@property (atomic) BOOL isRunning;

void socketCallBack(CFSocketRef s, CFSocketCallBackType callbackType, CFDataRef address, const void *data, void *info);

- (void) startListen;
- (void) doStartListen;
- (void) run;
- (void) stopListen;
- (void) doStopListen;

@end

@implementation OPListener

@synthesize socketRef = _socketRef;

- (CFSocketRef) getSocketRef {
    @synchronized(self) {
        return _socketRef;
    }
}

- (void) setSocketRef:(CFSocketRef)newSocketRef {
    @synchronized(self) {
        if (_socketRef != NULL) {
            CFSocketInvalidate(_socketRef);
        }
        _socketRef = newSocketRef;
    }
}

void socketCallBack(CFSocketRef s, CFSocketCallBackType callbackType, CFDataRef address, const void *data, void *info) {
    OPListener *this = (OPListener *)info;
    [this logMsg:@"socketCallBack"];

    switch (callbackType) {
        case kCFSocketAcceptCallBack: {
            CFSocketNativeHandle socketHandle;
            memcpy(&socketHandle, data, sizeof(CFSocketNativeHandle));

            CFReadStreamRef readStream;
            CFWriteStreamRef writeStream;
            CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketHandle, &readStream, &writeStream);
            if (readStream && writeStream) {
                CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                [this.delegate listener:this connectionWithInputStream:(NSInputStream *)readStream andOutputStream:(NSOutputStream *)writeStream];
            }
            else {
                close(socketHandle);
            }

            if (writeStream) {
                CFRelease(writeStream);
            }

            if (readStream) {
                CFRelease(readStream);
            }

        } break;

        default: {
            
        } break;
    }

}

- (BOOL) listenOnIPv4:(NSString *)ip andPort:(uint16)port {
    if (self.isRunning) {
        [self logMsg:@"Already listening on '%@:%i'", ip, port];
        return NO;
    }

    CFSocketContext socketContext;
    memset(&socketContext, 0, sizeof(socketContext));
    socketContext.info = self;

    self.socketRef =  CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, &socketCallBack, &socketContext);
    if (self.socketRef == NULL) {
        [self logMsg:@"Failed to create listen socket for '%@:%i'", ip, port];
        return NO;
    }

    struct sockaddr_in sin;

    memset(&sin, 0, sizeof(sin));
    sin.sin_len = sizeof(sin);
    sin.sin_family = AF_INET; /* Address family */
    sin.sin_port = htons(port); /* Or a specific port */
    inet_aton([ip cStringUsingEncoding:NSUTF8StringEncoding], &sin.sin_addr);

    CFDataRef sinData= CFDataCreate(kCFAllocatorDefault, (UInt8 *)&sin, sizeof(sin));
    CFSocketError socketError = CFSocketSetAddress(self.socketRef, sinData);
    CFRelease(sinData);

    if (socketError) {
        [self logMsg:@"failed to bind to '%@:%i'", ip, port];
        self.socketRef = NULL;
        return NO;
    }

    [self logMsg:@"start listening on '%@:%i'", ip, port];
    [self startListen];

    return YES; 
}

- (void) startListen {
    if (self.socketRef == NULL) {
        return;
    }

    [listenThread start];
    [self performSelector:@selector(doStartListen) onThread:listenThread withObject:NULL waitUntilDone:YES];
}

- (void) doStartListen {

}

- (void) run {
    [self logMsg:@"listening thread started"];
    @autoreleasepool {
        self.isRunning = YES;

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        CFRunLoopSourceRef socketSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.socketRef, 0);
        CFRunLoopAddSource([runLoop getCFRunLoop], socketSource, kCFRunLoopDefaultMode);

        while (self.isRunning && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);

        CFRunLoopRemoveSource([runLoop getCFRunLoop], socketSource, kCFRunLoopDefaultMode);
        CFRelease(socketSource);
    }
    [self logMsg:@"listening thread finished"];
}

- (void) doStopListen {
    self.isRunning = NO;
}

- (void) stopListen {
    if (self.isRunning) {
        [self performSelector:@selector(doStopListen) onThread:listenThread withObject:NULL waitUntilDone:YES];
    }
}

- (id) initWithDelegate:(id<OPListenerDelegate>)delegate {
    self = [super init];
    if (self) {
        self.delegate = delegate;
        _socketRef = NULL;
        self.isRunning = NO;
        listenThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
    }
    return self;
}

- (void) dealloc {
    [self stopListen];
    [listenThread release];
    self.socketRef = NULL;
    [super dealloc];
}

@end
