//
//  OPCircuit.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 06/03/14.
//
//

#import "OPConnection.h"
#import "OPJobDispatcher.h"
#import <security/Security.h>

NSString * const connectionIpKey = @"Ip";
NSString * const connectionPortKey = @"Port";

NSUInteger const cellSizeMax = 512;

@interface OPConnection() {
    NSThread *connectionThread;
    NSMutableArray *oBuffer;
    NSUInteger bytesSent;
}

@property (atomic) BOOL isRunning;
@property (retain) NSOutputStream *oStream;
@property (retain) NSInputStream *iStream;
@property (assign) OPConnectionHandshakeType handshakeType;

- (void) doConnectWithParams:(NSDictionary *)params;
- (void) startThread;
- (void) run;
- (void) doStopThread;
- (void) stopThread;
- (void) doDisconnect;
@end

@implementation OPConnection

@synthesize isConnected = _isConnected;

- (BOOL) connectToIp:(NSString *)ip port:(NSUInteger)port {
    @synchronized(self) {
        if (!self.isConnected) {
            //_isConnected = YES;
            NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                    ip, connectionIpKey,
                                    [NSNumber numberWithInteger:port], connectionPortKey, nil];
            
            [self startThread];
            [self performSelector:@selector(doConnectWithParams:) onThread:connectionThread withObject:params waitUntilDone:YES];
            
            if (!self.isConnected) {
                [self stopThread];
            }
            
            [self logMsg:@"connect"];
        }
    }
    return self.isConnected;
}

- (void) doConnectWithParams:(NSDictionary *)params {
    NSInputStream *iStream = nil;
    NSOutputStream *oStream = nil;
    
    NSString *ip = [params objectForKey:connectionIpKey];
    NSNumber *port = [params objectForKey:connectionPortKey];
    
    NSHost *host = [NSHost hostWithAddress:ip];
    [NSStream getStreamsToHost:host port:[port integerValue] inputStream:&iStream outputStream:&oStream];
    
    if (iStream == NULL || oStream == NULL) {
        // ...
        return;
    }
    
    _isConnected = YES;
    
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    
    self.oStream = oStream;
    self.iStream = iStream;
    
    [iStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
    [oStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
    
    NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
                              //[NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
                              [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                              [NSNumber numberWithBool:YES],  kCFStreamSSLValidatesCertificateChain,
                              kCFNull, kCFStreamSSLPeerName,
                              nil];
//    [iStream setProperty:settings forKey:kCFStreamPropertySSLSettings];
//    [oStream setProperty:settings forKey:kCFStreamPropertySSLSettings];
    
    CFReadStreamSetProperty((CFReadStreamRef)iStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);
    CFWriteStreamSetProperty((CFWriteStreamRef)oStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);
    
    [iStream setDelegate:self];
    [oStream setDelegate:self];
    
    [iStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    [oStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    
    [iStream open];
    [oStream open];
    
    [self logMsg:@"doConnect"];
}

- (void) startThread {
    [connectionThread start];
}

- (void) run {
    [self logMsg:@"connections thread started"];

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    self.isRunning = YES;
    
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    while (self.isRunning && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
    
    [pool release];
    
    [self logMsg:@"connections thread finished"];
}

- (void) doStopThread {
    self.isRunning = NO;
    [self logMsg:@"doStopThread"];
}

- (void) stopThread {
    [self performSelector:@selector(doStopThread) onThread:connectionThread withObject:NULL waitUntilDone:YES];
}

- (void) doDisconnect {
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    
    [self.iStream close];
    [self.oStream close];
    
    [self.iStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    [self.oStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    
    self.iStream = NULL;
    self.oStream = NULL;
    
    [self.delegate connection:self event:OPConnectionEventDisconnected object:NULL];
    [self logMsg:@"doDisconnect"];
}

- (void) disconnect {
    @synchronized(self) {
        if (self.isConnected) {
            _isConnected = NO;
            [self performSelector:@selector(doDisconnect) onThread:connectionThread withObject:NULL waitUntilDone:NO];
            [self stopThread];
            [self logMsg:@"disconnect"];
        }
    }
}

- (void) sendData:(NSData *)data {
    if (data == NULL || self.isConnected == NO) {
        return;
    }
    
    if ([data length] == 0) {
        return;
    }
    
    [self logMsg:@"Bytes to send %lu", (unsigned long)data.length];
    
    @synchronized(self) {
        [oBuffer addObject:data];
    }
    
    if (oBuffer.count == 1 && bytesSent == 0) {
        if ([self.oStream hasSpaceAvailable]) {
            bytesSent = [self.oStream write:data.bytes maxLength:data.length];
        }
    }
}

-(void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
    
    if (self.handshakeType == OPConnectionHandshkeUndefined) {
        if (streamEvent == NSStreamEventHasBytesAvailable || streamEvent == NSStreamEventHasSpaceAvailable) {
            NSArray *certs = [stream propertyForKey: (NSString *)kCFStreamPropertySSLPeerCertificates];
            //[self logMsg:@"%@ number of certs = %lu",[stream class], (unsigned long)[certs count]];

            if (certs.count == 0 || certs.count > 2) {
                [self logMsg:@"Initial handshake failed"];
                [self disconnect];
                return;
            }
            
            if (certs.count == 2) {
                self.handshakeType = OPConnectionHandshkeV1;
                [self logMsg:@"OPConnectionHandshkeV1"];
            }
            else {
                self.handshakeType = OPConnectionHandshkeV3;
                
                //SecCertificateRef certificate = (SecCertificateRef) [certs objectAtIndex:0];
                //SecKeyRef remoteSecKey = NULL;
                //SecCertificateCopyPublicKey(certificate, &remoteSecKey);
                //size_t keyLen = SecKeyGetBlockSize(remoteSecKey);
                //CFRelease(remoteSecKey);
                //
                //if (keyLen <= 128) {
                //    //[self logMsg:@"keyLen = '%zu'", keyLen];
                //    [self logMsg:@"OPConnectionHandshkeV2"];
                //    self.handshakeType = OPConnectionHandshkeV2;
                //}
                
                // certificate self-signed. NSStream did it for us??
                
                // TODO:
                // Check SecCertificateIsSelfSigned
                // Check Some component other than "commonName" is set in the subject or issuer DN of the certificate.
                // The commonName of the subject or issuer of the certificate ends with a suffix other than ".net".
                
                // NSDictionary *certValues = (NSDictionary *) SecCertificateCopyValues(certificate, NULL, NULL);
                // [self logMsg:@"%@", certValues];
                
                //[self logMsg:@"OPConnectionHandshkeV3"];
            }
            // check cifers
            //        CFDataRef data = (CFDataRef) CSReadtreamCopyProperty(stream, kCFStreamPropertySSLContext);
            //        SSLContextRef sslContext;
            //        CFDataGetBytes(data, CFRangeMake(0, sizeof(SSLContextRef)), (UInt8*)&sslContext);
            //        OSStatus SSLGetNumberEnabledCiphers (
            //                                             SSLContextRef context,
            //                                             size_t *numCiphers
            //                                             );
            //       OSStatus SSLGetEnabledCiphers (
            //                                       SSLContextRef context,
            //                                       SSLCipherSuite *ciphers,
            //                                       size_t *numCiphers
            //                                       );
        }
    }
    
    switch (streamEvent) {
        case NSStreamEventOpenCompleted: {
            [self logMsg:@"NSStreamEventOpenCompleted %@", [stream class]];
            if ([stream isKindOfClass:[NSOutputStream class]]) {
                [self.delegate connection:self event:OPConnectionEventConnected object:NULL];
            }
        } break;
            
        case NSStreamEventHasSpaceAvailable: {
            [self logMsg:@"NSStreamEventHasSpaceAvailable %@", [stream class]];
            if (oBuffer.count == 0) {
                bytesSent = 0;
                return;
            }
            NSData *data = [oBuffer objectAtIndex:0];
            if (bytesSent == data.length) {
                [self logMsg:@"Sent %lu bytes", (unsigned long)bytesSent];
                @synchronized(self) {
                    [oBuffer removeObjectAtIndex:0];
                }
                bytesSent = 0;
                if (oBuffer.count == 0) {
                    return;
                }
            }
            
            bytesSent += [self.oStream write:data.bytes + bytesSent maxLength:data.length - bytesSent];
        } break;
            
        case NSStreamEventHasBytesAvailable: {
            [self logMsg:@"NSStreamEventHasBytesAvailable %@", [stream class]];
            uint8_t iBuffer[cellSizeMax];
            NSInteger bytesReceived = 0;
            
            bytesReceived = [self.iStream read:iBuffer maxLength:cellSizeMax];
            if (bytesReceived < 0) {
                [self logMsg:@"InputStreamError: '%@'", [self.iStream streamError]];
                
            }
            else if (bytesReceived > 0) {
                [self.delegate connection:self event:OPConnectionEventDataReceived object:[NSData dataWithBytes:iBuffer length:bytesReceived]];
            }
        } break;
            
        case NSStreamEventEndEncountered: {
            [self logMsg:@"NSStreamEventEndEncountered %@", [stream class]];
            [self disconnect];
        } break;
            
        case NSStreamEventErrorOccurred: {
            [self logMsg:@"NSStreamEventErrorOccurred %@", [stream class]];
            [self disconnect];
        } break;
            
        case NSStreamEventNone: {
            [self logMsg:@"NSStreamEventNone %@", [stream class]];
        } break;
    }
}

- (id) init {
    self = [super init];
    if (self) {
        _isConnected = NO;
        self.delegate = NULL;
        
        self.handshakeType = OPConnectionHandshkeUndefined;
        
        oBuffer = [[NSMutableArray alloc] init];
        bytesSent = 0;
        
        self.isRunning = YES;
        connectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
    }
    return self;
}

- (void) dealloc {
    [self disconnect];
    [connectionThread release];
    
    [oBuffer release];
    
    [super dealloc];
}

@end
