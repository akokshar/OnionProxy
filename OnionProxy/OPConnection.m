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

NSUInteger const OPCellSizeMax = 512;
NSUInteger const OPCellPayloadLen = 509;

#pragma pack (1)
typedef struct {
    uint16_t circuitID;
    uint8_t command;
    uint8_t payload[];
} OPCell;
#pragma pack()

#pragma pack(1)
typedef struct {
    uint16_t length;
    uint8_t data[];
} OPCellPayload;
#pragma pack()

//// Fixed-length cell
//uint8_t const commandCellPadding = 0;   //(Padding)                 (See Sec 7.2)
//uint8_t const commandCellCreate = 1;    //(Create a circuit)        (See Sec 5.1)
//uint8_t const commandCellCreated = 2;   //(Acknowledge create)      (See Sec 5.1)
////3 -- RELAY       //(End-to-end data)         (See Sec 5.5 and 6)
//uint8_t const commandCellDestroy = 4;   //(Stop using a circuit)    (See Sec 5.4)
////5 -- CREATE_FAST //(Create a circuit, no PK) (See Sec 5.1)
////6 -- CREATED_FAST// (Circuit created, no PK) (See Sec 5.1)
//uint8_t const commandCellNetinfo = 8;   //(Time and address info)   (See Sec 4.5)
////9 -- RELAY_EARLY //(End-to-end data; limited)(See Sec 5.6)
//uint8_t const commandCellCreate2 = 10;  //(Extended CREATE cell)    (See Sec 5.1)
//uint8_t const commandCellCreated2 = 11; //(Extended CREATED cell)   (See Sec 5.1)
//
//// Variable-length command values
//uint8_t const commandCellVersions = 7;  //(Negotiate proto version) (See Sec 4)
////128 -- VPADDING  //(Variable-length padding) (See Sec 7.2)
//uint8_t const commandCellCerts = 129;    //(Certificates)            (See Sec 4.2)
//uint8_t const commandCellAuthChallenge = 130;   //(Challenge value)    (See Sec 4.3)
//uint8_t const commandCellAuthenticate = 131;    //(Client authentication)(See Sec 4.5)
////132 -- AUTHORIZE //(Client authorization)    (Not yet used)

@interface OPConnection() {
    NSThread *connectionThread;
    NSMutableArray *oBuffer;
    NSUInteger bytesSent;
    NSMutableData *iBuffer;
    NSUInteger bytesReceived;
}

@property (atomic) BOOL isRunning;
@property (retain) NSOutputStream *oStream;
@property (retain) NSInputStream *iStream;
@property (assign) OPConnectionHandshakeType handshakeType;
@property (assign) OPConnectionProtocolVersion protocolVersion;
@property (retain) NSArray *tlsCertificates;

- (void) doConnectWithParams:(NSDictionary *)params;
- (void) startThread;
- (void) run;
- (void) doStopThread;
- (void) stopThread;
- (void) doDisconnect;

- (uint16_t) generateCircuitID;
- (BOOL) isVariableLenCellWithCommand:(OPConnectionCommand)command;
- (void) queueCellWithCommand:(OPConnectionCommand)command andData:(NSData *)data;

@end

@implementation OPConnection

@synthesize isConnected = _isConnected;

@synthesize circuitID = _circuitID;

- (uint16_t) getCircuitID {
    if (_circuitID == 0) {
        _circuitID = [self generateCircuitID];
    }
    return _circuitID;
}

- (uint16_t) generateCircuitID {
    static uint16_t lastID = 0;
    return lastID + arc4random() % 13;
}

- (BOOL) connectToIp:(NSString *)ip port:(NSUInteger)port {
    @synchronized(self) {
        if (!self.isConnected) {
            //_isConnected = YES;
            NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                    ip, connectionIpKey,
                                    [NSNumber numberWithInteger:port], connectionPortKey, nil];
            
            [self startThread]; //TODO: this must be causing Spinlock in Run method. Rework this later (remove Port from runloop)
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
                              [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                              [NSNumber numberWithBool:YES], kCFStreamSSLValidatesCertificateChain,
                              kCFNull, kCFStreamSSLPeerName,
                              nil];
    
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
    
    [self.delegate connection:self onEvent:OPConnectionEventDisconnected];
    [self logMsg:@"doDisconnect"];
}

- (void) disconnect {
    @synchronized(self) {
        if (self.isConnected) {
            _isConnected = NO;
            [self performSelector:@selector(doDisconnect) onThread:connectionThread withObject:NULL waitUntilDone:NO];
            [self stopThread];
            [iBuffer setLength:0];
            [oBuffer removeAllObjects];
            [self logMsg:@"disconnect"];
        }
    }
}

- (BOOL) isVariableLenCellWithCommand:(OPConnectionCommand)command {
    switch (self.protocolVersion) {
        case OPConnectionProtocolVersionV3: {
            if (command == OPConnectionCommandVersions || command >= 128) {
                return YES;
            }
        } break;
            
        case OPConnectionProtocolVersionV2: {
            if (command == OPConnectionCommandVersions) {
                return YES;
            }
        } break;
            
        case OPConnectionProtocolVersionV1: {
            return NO;
        }
            
        case OPConnectionProtocolVersionUnknown: {
            if (command == OPConnectionCommandVersions || command >= 128) {
                return YES;
            }
        }
    }
    return NO;
}

- (void) queueCellWithCommand:(OPConnectionCommand)command andData:(NSData *)data {
    NSMutableData *cell = [[NSMutableData alloc] initWithCapacity:sizeof(OPCell) + sizeof(OPCellPayload) + data.length];
    OPCell header;
    header.circuitID = CFSwapInt16HostToBig(self.circuitID);
    header.command = command;
    [cell appendBytes:&header length:sizeof(OPCell)];
    
    if ([self isVariableLenCellWithCommand:command]) {
        OPCellPayload payload;
        payload.length = CFSwapInt16HostToBig(data.length);
        [cell appendBytes:&payload length:sizeof(OPCellPayload)];
        [cell appendData:data];
    }
    else {
        [cell appendData:data];
    }
    
    @synchronized(self) {
        [oBuffer addObject:cell];
    }
    
    [cell release];
}

- (void) sendCommand:(OPConnectionCommand)command withData:(NSData *)data; {
    if (data == NULL || self.isConnected == NO) {
        return;
    }
    
    if ([data length] == 0) {
        return;
    }

    [self queueCellWithCommand:command andData:data];
    
    if (oBuffer.count == 1 && bytesSent == 0) {
        if ([self.oStream hasSpaceAvailable]) {
            NSData *dataToSend = [oBuffer objectAtIndex:0];
            bytesSent = [self.oStream write:dataToSend.bytes maxLength:dataToSend.length];
        }
    }
}

-(void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
    
    //By the time your stream delegate’s event handler gets called to indicate that there is space available on the socket,
    //the operating system has already constructed a TLS channel, obtained a certificate chain from the other end of the connection,
    //and created a trust object to evaluate it
    if (self.tlsCertificates == NULL) {
        if (streamEvent == NSStreamEventHasSpaceAvailable) {

            self.tlsCertificates = [stream propertyForKey: (NSString *)kCFStreamPropertySSLPeerCertificates];
            //[self logMsg:@"%@ number of certs = %lu",[stream class], (unsigned long)[certs count]];

            if (self.tlsCertificates.count == 0 || self.tlsCertificates.count > 2) {
                [self logMsg:@"Initial handshake failed"];
                [self disconnect];
                return;
            }
            
            if (self.tlsCertificates.count == 2) {
                self.handshakeType = OPConnectionHandshkeCertificatesUpFront;
                self.protocolVersion = OPConnectionProtocolVersionV1;
                [self logMsg:@"OPConnectionHandshkeV1"];
                [self disconnect]; // hot going to support this for now
                return;
            }
            else {
                self.handshakeType = OPConnectionHandshkeRenegotiation;
                
                //There are additionally a set of constraints on the connection certificate,
                //which the initiator can use to learn that the in-protocol handshake is in use.
                //Specifically, at least one of these properties must be true of the certificate:
                
                // Is certificate self-signed
                SecTrustRef trust = (SecTrustRef)[stream propertyForKey: (NSString *)kCFStreamPropertySSLPeerTrust];
                SecTrustSetAnchorCertificates(trust, (CFArrayRef)self.tlsCertificates);
                SecTrustResultType result;
                SecTrustEvaluate(trust, &result);
                [self logMsg:@"cert evaluation result = %i", result];
                
                if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
                    self.handshakeType = OPConnectionHandshkeInProtocol;
                }
                else {
                    // Is The certificate's public key modulus is longer than 1024 bits
                    SecCertificateRef cert = (SecCertificateRef)[self.tlsCertificates objectAtIndex:0];
                    SecKeyRef pubKey;
                    SecCertificateCopyPublicKey(cert, &pubKey);
                    size_t keySize = SecKeyGetBlockSize(pubKey);
                    if (keySize > 128) {
                        self.handshakeType = OPConnectionHandshkeInProtocol;
                    }
                    CFRelease(pubKey);
                    
                    if (self.handshakeType == OPConnectionHandshkeRenegotiation) {
                        // Some component other than "commonName" is set in the subject or issuer DN of the certificate
                        //TODO
                    }
                    else {
                        // The commonName of the subject or issuer of the certificate ends with a suffix other than ".net".
                        //TODO
                    }

                }

                
                [self logMsg:@"OPConnectionHandshake=%i", self.handshakeType];
                
            }
        }
    }
    
    switch (streamEvent) {
        case NSStreamEventOpenCompleted: {
            //[self logMsg:@"NSStreamEventOpenCompleted %@", [stream class]];
            
            if ([stream isKindOfClass:[NSOutputStream class]]) {
                [oBuffer removeAllObjects];
                
                // In versions higher then v1 (renegotiation and in-protocol) Version Cell have to be send first
                if (self.protocolVersion != OPConnectionProtocolVersionV1) {
                    uint16_t versions[] = { CFSwapInt16HostToBig(3), CFSwapInt16HostToBig(2) };
                    [self queueCellWithCommand:OPConnectionCommandVersions andData:[NSData dataWithBytes:versions length:sizeof(versions)]];
                }
            }
            
            if ([stream isKindOfClass:[NSInputStream class]]) {
                [iBuffer setLength:0];
            }
        } break;
            
        case NSStreamEventHasSpaceAvailable: {
            //[self logMsg:@"NSStreamEventHasSpaceAvailable %@", [stream class]];
            
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
            //[self logMsg:@"NSStreamEventHasBytesAvailable %@", [stream class]];
            uint8_t buf[OPCellSizeMax];
            NSInteger len = 0;
            len = [self.iStream read:buf maxLength:OPCellSizeMax];
            
            if (len < 0) {
                [self logMsg:@"InputStreamError: '%@'", [self.iStream streamError]];
                return;
            }
            else if (len == 0) {
                return;
            }
            
            [iBuffer appendBytes:buf length:len];
            
            while (iBuffer.length >= sizeof(OPCell)) {
                OPCell *cell = (OPCell *)iBuffer.bytes;
                uint16_t cellLen;
                
                if ([self isVariableLenCellWithCommand:cell->command]) {
                    if (iBuffer.length < sizeof(OPCell) + sizeof(OPCellPayload)) {
                        return;
                    }
                    OPCellPayload *payload = (OPCellPayload *)cell->payload;
                    cellLen = sizeof(OPCell) + sizeof(OPCellPayload) + CFSwapInt16BigToHost(payload->length);
                }
                else {
                    cellLen = sizeof(OPCell) + OPCellPayloadLen;
                }
                
                if (iBuffer.length < cellLen) {
                    return;
                }

                if (cell->command == OPConnectionCommandVersions) {
                    if (self.protocolVersion != OPConnectionProtocolVersionUnknown) {
                        [self logMsg:@"Unexpected Versions cell received. Disconnecting."];
                        [self disconnect];
                        return;
                    }
                    
                    OPCellPayload *payload = (OPCellPayload *)cell->payload;
                    uint16_t dataLen = CFSwapInt16BigToHost(payload->length);

                    if (dataLen % 2 != 0) {
                        [self disconnect];
                        return;
                    }
                    
                    uint16_t *serverVersions = (uint16_t *)payload->data;
                    for (int i = 0; i < dataLen / 2; i++) {
                        uint16_t serverVersion = CFSwapInt16BigToHost(serverVersions[i]);
                        if (serverVersion == OPConnectionProtocolVersionV3 && self.protocolVersion < OPConnectionProtocolVersionV3) {
                            self.protocolVersion = OPConnectionProtocolVersionV3;
                        }
                        else if (serverVersion == OPConnectionProtocolVersionV2 && self.protocolVersion < OPConnectionProtocolVersionV2) {
                            self.protocolVersion = OPConnectionProtocolVersionV2;
                        }
                    }
                    
                    if (self.protocolVersion == OPConnectionProtocolVersionUnknown) {
                        [self logMsg:@"Failed to negotiate protocol version"];
                        [self.delegate connection:self onEvent:OPConnectionEventConnectionFailed];
                        [self disconnect];
                        return;
                    }
                    else {
                        [self.delegate connection:self onEvent:OPConnectionEventConnected];
                    }
                }
                else {
                    if ([self isVariableLenCellWithCommand:cell->command]) {
                        OPCellPayload *payload = (OPCellPayload *)cell->payload;
                        uint16_t dataLen = CFSwapInt16BigToHost(payload->length);
                        [self.delegate connection:self onCommand:cell->command withData:[NSData dataWithBytes:payload->data length:dataLen]];
                    }
                    else {
                        [self.delegate connection:self onCommand:cell->command withData:[NSData dataWithBytes:cell->payload length:OPCellPayloadLen]];
                    }
                }
                
                [iBuffer replaceBytesInRange:NSMakeRange(0, cellLen) withBytes:NULL length:0];
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
        
        _circuitID = 0;
        
        self.handshakeType = OPConnectionHandshkeUnknown;
        self.protocolVersion = OPConnectionProtocolVersionUnknown;
        
        self.tlsCertificates = NULL;
        
        oBuffer = [[NSMutableArray alloc] init];
        bytesSent = 0;
        
        iBuffer = [[NSMutableData alloc] initWithCapacity:OPCellSizeMax];
        bytesReceived = 0;
        
        self.isRunning = YES;
        connectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
    }
    return self;
}

- (void) dealloc {
    [self disconnect];
    [connectionThread release];
    
    self.tlsCertificates = NULL;
    
    [oBuffer release];
    [iBuffer release];
    
    [super dealloc];
}

@end
