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

#pragma pack(1)
typedef struct {
    uint8_t certsCount;
    uint8_t certsData[];
} OPCerts;
#pragma pack()

#pragma pack(1)
typedef struct {
    uint8_t certType;
    uint16_t certLen;
    uint8_t certData[];
} OPCert;
#pragma pack()

#pragma pack(1)
typedef struct {
    uint8_t type;
    uint8_t length;
    uint8_t value[];
} OPTlv;
#pragma pack()

@interface OPConnection() {
    NSThread *connectionThread;
    NSMutableArray *oBuffer;
    NSUInteger bytesSent;
    NSMutableData *iBuffer;
    NSUInteger bytesReceived;
}

@property (retain) OPTorNode *node;

@property (atomic) BOOL isRunning;
@property (atomic) BOOL isConnected;
@property (retain) NSOutputStream *oStream;
@property (retain) NSInputStream *iStream;
@property (assign) OPConnectionHandshakeType handshakeType;
@property (assign) OPConnectionProtocolVersion protocolVersion;

@property (assign) id <OPConnectionDelegate> delegate;

- (void) startThread;
- (void) doWait;
- (void) run;
- (void) doStopThread;
- (void) stopThread;
- (void) doDisconnect;

- (BOOL) isVariableLenCellWithCommand:(OPConnectionCommand)command;
- (void) queueCellWithCommand:(OPConnectionCommand)command andData:(NSData *)data;
- (void) processCell:(OPCell *)cell;
- (void) doProcessCell:(OPCell *)cell;

@end

@implementation OPConnection

@synthesize isConnected;

@synthesize circuitID = _circuitID;

- (uint16_t) getCircuitID {
    if (_circuitID == 0) {
        static uint16_t lastID = 0;
        _circuitID = lastID + arc4random() % 13 + 1;
    }
    return _circuitID;
}

- (BOOL) connectToNode:(OPTorNode *)node {
    if (node == NULL) {
        return NO;
    }
    self.node = node;
    [self startThread];
    [self performSelector:@selector(doWait) onThread:connectionThread withObject:NULL waitUntilDone:YES];
    return self.isConnected;
}

- (void) doWait {
    
}

- (void) startThread {
    if ([connectionThread isExecuting]) {
        return;
    }
    self.isRunning = YES;
    [connectionThread start];
}

- (void) run {
    [self logMsg:@"connections thread started"];

    @autoreleasepool {
        //NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        
        NSInputStream *iStream = nil;
        NSOutputStream *oStream = nil;
        
        [NSStream getStreamsToHostWithName:self.node.ipStr port:self.node.orPort inputStream:&iStream outputStream:&oStream];

        if (iStream == NULL || oStream == NULL) {
            [iStream release];
            [oStream release];
            return;
        }
        
        self.oStream = oStream;
        self.iStream = iStream;
        
        [iStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
        [oStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];

        NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                                  [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
                                  kCFNull, kCFStreamSSLPeerName,
                                  nil];
        
        CFReadStreamSetProperty((CFReadStreamRef)iStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);
        CFWriteStreamSetProperty((CFWriteStreamRef)oStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);

        [settings release];

        [iStream setDelegate:self];
        [oStream setDelegate:self];

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

        [iStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        [oStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        
        [iStream open];
        [oStream open];
        
        self.isConnected = YES;
        
        while (self.isRunning && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
        
        [self.iStream close];
        [self.oStream close];
        
        [self.iStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        [self.oStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        
        self.iStream = NULL;
        self.oStream = NULL;
        
        [iBuffer setLength:0];
        [oBuffer removeAllObjects];
        
        //[pool release];
    }
    
    [self logMsg:@"connections thread finished"];
}

- (void) doStopThread {
    self.isRunning = NO;
    [self logMsg:@"doStopThread"];
}

- (void) stopThread {
    if (self.isRunning) {
        [self performSelector:@selector(doStopThread) onThread:connectionThread withObject:NULL waitUntilDone:YES];
    }
}

- (void) doDisconnect {
    [self logMsg:@"doDisconnect"];
}

- (void) disconnect {
    if (self.isConnected == YES) {
        self.isConnected = NO;
        //[self performSelector:@selector(doDisconnect) onThread:connectionThread withObject:NULL waitUntilDone:NO];
        [self stopThread];
        [self.delegate connection:self onEvent:OPConnectionEventDisconnected];
        [self logMsg:@"disconnect"];
    }
    else {
        [self logMsg:@"not connected"];
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
        cell.length = OPCellSizeMax;
    }
    
    @synchronized(self) {
        [oBuffer addObject:cell];
    }
    
    [cell release];
}

- (void) sendCommand:(OPConnectionCommand)command withData:(NSData *)data {
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

NSString *isCerificateCheckedKey = @"isOPCerificateChecked";

-(void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
    
    //By the time your stream delegate’s event handler gets called to indicate that there is space available on the socket,
    //the operating system has already constructed a TLS channel, obtained a certificate chain from the other end of the connection,
    //and created a trust object to evaluate it
    if (streamEvent == NSStreamEventHasSpaceAvailable) {
        NSNumber *isCerificateChecked = [stream propertyForKey: isCerificateCheckedKey];
        if (!isCerificateChecked || ![isCerificateChecked boolValue]) {
            [stream setProperty:[NSNumber numberWithBool:YES] forKey:isCerificateCheckedKey];
        
            NSArray *certs = [stream propertyForKey: (NSString *)kCFStreamPropertySSLPeerCertificates];
            //[self logMsg:@"%@ number of certs = %lu",[stream class], (unsigned long)[certs count]];

            if (certs.count == 0 || certs.count > 2) {
                [self logMsg:@"Initial handshake failed"];
                [self disconnect];
                return;
            }
            
            if (certs.count == 2) {
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
                SecTrustSetAnchorCertificates(trust, (CFArrayRef)certs);
                SecTrustResultType result;
                SecTrustEvaluate(trust, &result);
                [self logMsg:@"cert evaluation result = %i", result];
                
                if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
                    self.handshakeType = OPConnectionHandshkeInProtocol;
                }
                else {
                    // Is The certificate's public key modulus is longer than 1024 bits
                    SecCertificateRef cert = (SecCertificateRef)[certs objectAtIndex:0];
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
            [self logMsg:@"NSStreamEventOpenCompleted %@", [stream class]];
            
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
                OPCell *cell = (OPCell *)data.bytes;
                [self logMsg:@"Sent %lu bytes. CircuitID=%i, Command=%i", (unsigned long)bytesSent, CFSwapInt16BigToHost(cell->circuitID), cell->command];
                @synchronized(self) {
                    [oBuffer removeObjectAtIndex:0];
                }
                bytesSent = 0;
                if (oBuffer.count == 0) {
                    return;
                }
                data = [oBuffer objectAtIndex:0];
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
                
                [self processCell:cell];
                
                // stop if error during processing cell was fatal and led to disconnection
                if (!self.isConnected) {
                    return;
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

- (void) processCell:(OPCell *)cell {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [self doProcessCell:cell];
    [pool release];
}

- (void) doProcessCell:(OPCell *)cell {
    switch (cell->command) {
        case OPConnectionCommandNetInfo: {
            [self logMsg:@"OPConnectionCommandNetInfo"];
            
            // Timestamp              [4 bytes]
            // Other OR's address     [variable]
            // Number of addresses    [1 byte]
            // This OR's addresses    [variable]
            
            uint8_t *data = cell->payload;
            int pos = 0;
            
            uint32_t timestamp;
            memcpy((uint8_t *)&timestamp, data, sizeof(uint32_t));
            timestamp = CFSwapInt32BigToHost(timestamp);
            pos += sizeof(uint32_t);
            
            OPTlv *myAddr = (OPTlv *)(data + pos);
            pos += sizeof(OPTlv) + myAddr->length;
            
            uint8_t numOfAddr = (data + pos)[0];
            pos += 1;
            
            OPTlv *orAddr = NULL;
            
            for (int i = 0; orAddr == NULL && i < numOfAddr && pos < OPCellPayloadLen - sizeof(OPTlv); i++) {
                OPTlv *addr = (OPTlv *)(data + pos);
                pos += sizeof(OPTlv) + addr->length;
                
                if (pos > OPCellPayloadLen) {
                    [self logMsg:@"Malformed NetInfo Cell"];
                    [self disconnect];
                    return;
                }
                
                // 0x00 -- Hostname
                // 0x04 -- IPv4 address
                // 0x06 -- IPv6 address
                // 0xF0 -- Error, transient
                // 0xF1 -- Error, nontransient
                
                if (addr->type == 0x4 && addr->length == 4) {
                    uint32_t ip;
                    memcpy(&ip, addr->value, 4);
                    
                    if (ip == self.node.ip) {
                        orAddr = addr;
                    }
                }
            }
            
            if (orAddr == NULL) {
                [self logMsg:@"Router anounced address does not match one from consensus"];
                [self disconnect];
                return;
            }
            
            NSMutableData *netInfo = [[NSMutableData alloc] init];
            
            timestamp = (uint32_t) [[NSDate date] timeIntervalSince1970];
            timestamp = CFSwapInt32HostToBig(timestamp);
            [netInfo appendBytes:&timestamp length:sizeof(uint32_t)];
            
            [netInfo appendBytes:orAddr length:sizeof(OPTlv) + orAddr->length];
            
            numOfAddr = 1;
            [netInfo appendBytes:&numOfAddr length:sizeof(numOfAddr)];
            [netInfo appendBytes:myAddr length:sizeof(OPTlv) + myAddr->length];
            [netInfo setLength:OPCellPayloadLen];
            [self sendCommand:OPConnectionCommandNetInfo withData:netInfo];
            [netInfo release];
            
            [self.delegate connection:self onEvent:OPConnectionEventConnected];

        } break;
            
        case OPConnectionCommandAuthChallenge: {
            
        } break;
        
        case OPConnectionCommandCerts: {
            [self logMsg:@"OPConnectionCommandCerts"];

            OPCellPayload *payload = (OPCellPayload *)cell->payload;
            uint16_t dataLen = CFSwapInt16BigToHost(payload->length);
            
            if (dataLen < sizeof(OPCerts)) {
                [self logMsg:@"Malformed Certs Cell (1)"];
                [self disconnect];
                return;
            }
            
            OPCerts *certs = (OPCerts *)payload->data;
            if (certs->certsCount != 2) {
                [self logMsg:@"Malformed Certs Cell (2)"];
                [self disconnect];
                return;
            }
            
            dataLen -= sizeof(OPCerts);
            if (dataLen < sizeof(OPCert)) {
                [self logMsg:@"Malformed Certs Cell (3)"];
                [self disconnect];
                return;
            }
            
            OPCert *cert1 = (OPCert *)certs->certsData;
            uint16_t cert1Len = CFSwapInt16BigToHost(cert1->certLen);
            
            dataLen -= sizeof(OPCert);
            if (dataLen < cert1Len) {
                [self logMsg:@"Malformed Certs Cell (4)"];
                [self disconnect];
                return;
            }
            
            dataLen -= cert1Len;
            if (dataLen < sizeof(OPCert)) {
                [self logMsg:@"Malformed Certs Cell (5)"];
                [self disconnect];
                return;
            }
            
            OPCert *cert2 = (OPCert *)(certs->certsData + sizeof(OPCert) + cert1Len);
            uint16_t cert2Len = CFSwapInt16BigToHost(cert2->certLen);
            
            if (dataLen < cert2Len) {
                [self logMsg:@"Malformed Certs Cell (6)"];
                [self disconnect];
                return;
            }
            
            if ((cert1->certType == 1 && cert2->certType != 2) || (cert1->certType == 2 && cert2->certType != 1)) {
                [self logMsg:@"Malformed Certs Cell (7)"];
                [self disconnect];
                return;
            }
            
            NSData *cert1Data = [[NSData alloc] initWithBytes:cert1->certData length:cert1Len];
            NSData *cert2Data = [[NSData alloc] initWithBytes:cert2->certData length:cert2Len];
            
//            SecCertificateRef secCertificate1 = SecCertificateCreateWithData(NULL, (CFDataRef)cert1Data);
//            SecCertificateRef secCertificate2 = SecCertificateCreateWithData(NULL, (CFDataRef)cert1Data);

            [cert1Data release];
            [cert2Data release];

        } break;
            
        case OPConnectionCommandVersions: {
            [self logMsg:@"OPConnectionCommandVersions"];
            
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

        } break;

        default: {
            [self logMsg:@"OPConnectionCommand %i", cell->command];
            
            if ([self isVariableLenCellWithCommand:cell->command]) {
                OPCellPayload *payload = (OPCellPayload *)cell->payload;
                uint16_t dataLen = CFSwapInt16BigToHost(payload->length);
                [self.delegate connection:self onCommand:cell->command withData:[NSData dataWithBytes:payload->data length:dataLen]];
            }
            else {
                [self.delegate connection:self onCommand:cell->command withData:[NSData dataWithBytes:cell->payload length:OPCellPayloadLen]];
            }
        } break;
            
    }
    
}

- (id) initWithDelegate:(id<OPConnectionDelegate>)delegate {
    self = [super init];
    if (self) {
        self.isConnected = NO;
        self.delegate = delegate;
        
        _circuitID = 0;
        
        self.handshakeType = OPConnectionHandshkeUnknown;
        self.protocolVersion = OPConnectionProtocolVersionUnknown;
        
        oBuffer = [[NSMutableArray alloc] init];
        bytesSent = 0;
        
        iBuffer = [[NSMutableData alloc] initWithCapacity:OPCellSizeMax];
        bytesReceived = 0;
        
        self.isRunning = NO;
        connectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:NULL];
    }
    return self;
}

- (void) dealloc {
    [self disconnect];
    [connectionThread release];
    
    [oBuffer release];
    [iBuffer release];
    
    self.node = NULL;
    self.delegate = NULL;
    
    [super dealloc];
}

+ (OPConnection *) connectionWithDelegate:(id<OPConnectionDelegate>)delegate {
    OPConnection *connection = [[OPConnection alloc] initWithDelegate:delegate];
    return [connection autorelease];
}

@end
