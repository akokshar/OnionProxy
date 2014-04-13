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

- (void) doConnectWithParams:(NSDictionary *)params;
- (void) startThread;
- (void) run;
- (void) doStopThread;
- (void) stopThread;
- (void) doDisconnect;

+ (uint16_t) generateCircuitID;
- (BOOL) isVariableLenCellOfCommand:(OPConnectionCommand)command;

@end

@implementation OPConnection

@synthesize isConnected = _isConnected;

@synthesize circuitID = _circuitID;

- (uint16_t) getCircuitID {
    if (_circuitID == 0) {
        _circuitID = [OPConnection generateCircuitID];
    }
    return _circuitID;
}

+ (uint16_t) generateCircuitID {
    static uint16_t lastID = 0;
    return lastID + arc4random() % 13;
}

- (BOOL) isVariableLenCellOfCommand:(OPConnectionCommand)command {
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

- (BOOL) connectToIp:(NSString *)ip port:(NSUInteger)port {
    @synchronized(self) {
        if (!self.isConnected) {
            //_isConnected = YES;
            NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                    ip, connectionIpKey,
                                    [NSNumber numberWithInteger:port], connectionPortKey, nil];
            
            [self startThread]; //TODO: this must be causing Spinlock in Run method. Rework this later
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
                              [NSNumber numberWithBool:YES],  kCFStreamSSLValidatesCertificateChain,
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
    
    if (self.handshakeType == OPConnectionHandshkeUnknown) {
        if (streamEvent == NSStreamEventHasBytesAvailable || streamEvent == NSStreamEventHasSpaceAvailable) {
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
                // certificate self-signed. NSStream did it for us??
                self.handshakeType = OPConnectionHandshkeInProtocol;
                [self logMsg:@"OPConnectionHandshkeV3"];
                
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
                    size_t cellSize = sizeof(OPCell) + sizeof(OPCellPayload) + sizeof(versions);
                    
                    OPCell *versionsCell = malloc(cellSize);
                    versionsCell->circuitID = self.circuitID;
                    versionsCell->command = OPConnectionCommandVersions;
                    
                    OPCellPayload *payload = (OPCellPayload *) versionsCell->payload;
                    payload->length = CFSwapInt16HostToBig(sizeof(versions));
                    memcpy(payload->data, versions, sizeof(versions));
                    
                    //[self logMsg:@"Versions Cell data '%@' sizeof %lu", [NSData dataWithBytes:versionsCell length:cellSize], cellSize];
                    [oBuffer addObject:[NSData dataWithBytes:versionsCell length:cellSize]];
                    
                    free(versionsCell);
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
                
                if ([self isVariableLenCellOfCommand:cell->command]) {
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
                    if ([self isVariableLenCellOfCommand:cell->command]) {
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
    
    [oBuffer release];
    [iBuffer release];
    
    [super dealloc];
}

@end
