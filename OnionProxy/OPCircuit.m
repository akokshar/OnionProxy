//
//  OPCircuit.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/03/14.
//
//

#import "OPCircuit.h"
#import "OPConfig.h"
#import "OPTorNode.h"
#import "OPTorDirectory.h"
#import "OPConnection.h"
#import "OPSimmetricKey.h"
#import "OPDiffieHellman.h"
#import "OPSHA1.h"

typedef enum {
    OPRelayCommandBegin = 1,     // RELAY_BEGIN     [forward]
    OPRelayCommandRelay = 2,     // RELAY_DATA      [forward or backward]
    OPRelayCommandEnd = 3,       // RELAY_END       [forward or backward]
    OPRelayCommandConnected = 4, // RELAY_CONNECTED [backward]
    OPRelayCommandSendMe = 5,    // RELAY_SENDME    [forward or backward] [sometimes control]
    OPRelayCommandExtend = 6,    // RELAY_EXTEND    [forward]             [control]
    OPRelayCommandExtended = 7,  // RELAY_EXTENDED  [backward]            [control]
    OPRelayCommandTruncate = 8,  // RELAY_TRUNCATE  [forward]             [control]
    OPRelayCommandTruncated = 9, // RELAY_TRUNCATED [backward]            [control]
    OPRelayCommandDrop = 10,     // RELAY_DROP      [forward or backward] [control]
    OPRelayCommandResolve = 11,  // RELAY_RESOLVE   [forward]
    OPRelayCommandResolved = 12, // RELAY_RESOLVED  [backward]
    OPRelayCommandBeginDir = 13, // RELAY_BEGIN_DIR [forward]
    OPRelayCommandExtend2 = 14,  // RELAY_EXTEND2   [forward]             [control]
    OPRelayCommandExtended2 = 15 // RELAY_EXTENDED2 [backward]            [control]
    //32..40 -- Used for hidden services; see rend-spec.txt.
} OPRelayCommand;

#pragma pack(1)
typedef struct {
    uint8 relayCommand;
    uint16 recognized;
    uint16 streamId;
    uint32 digest;
    uint16 length;
    uint8 payload[];
} OPRelayCellPayload;
#pragma pack()

NSString * const kOPCircuitNodeKey = @"NodeKey";
NSString * const kOPCircuitNodeReadyKey = @"NodeReady";
NSString * const kOPCircuitHandshakeKey = @"HandshakeKey";
NSString * const kOPCircuitForwardDigestKey = @"ForwardDigestKey";
NSString * const kOPCircuitBackwardDigestKey = @"BackwardDigestKey";
NSString * const kOPCircuitForwardSimmetricKeyKey = @"ForwardSimmetricKeyKey";
NSString * const kOPCircuitBackwardSimmetricKeyKey = @"BackwardSimmetricKeyKey";
NSString * const kOPCircuitNodeSentCommand = @"SentCommand";

NSString * const kOPStreamDelegateKey = @"DelegateKey";
NSString * const kOPStreamIsConnectedKey = @"IsConnectedKey";
NSString * const kOPStreamExitNodeIndex = @"ExitNodeIndex";

@interface OPCircuit() {
    NSUInteger needLength;
    OPStreamId streamIdCounter;
}

@property (atomic) BOOL isBusy;

@property (retain) OPConnection *connection;
@property (retain) NSMutableArray *nodes;
/// tail node index
@property (readonly, getter=getTailNodeIndex) NSUInteger tailNodeIndex;
@property (readonly, getter=getDirectoryNodeIndex) NSInteger directoryNodeIndex;
@property (retain) NSMutableDictionary *streams;

- (OPStreamId) addEmptyStreamCtx;
- (NSMutableDictionary *) getStreamCtxWithStreamId:(OPStreamId)streamId;
- (void) removeStreamCtxWithStreamId:(OPStreamId)streamId;

- (BOOL) canExtendTo:(OPTorNode *)node;
- (BOOL) canExtend;
- (void) extendToNode:(OPTorNode *)node;
- (void) extend;
- (void) extendFinishWithResult:(BOOL)result;
- (void) trancate;

/**
 *  return handshake data to be sent to the last router
 */
- (NSData *) handshakeRequestData;

/**
 *  Finish handshake with the last router, setup keys and digests
 */
- (BOOL) handshakeFinishWithResponseData:(NSData *)data;

- (void) relayCommand:(OPRelayCommand)command toNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data;
- (void) processCommand:(OPRelayCommand)command fromNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data;

@end

@implementation OPCircuit

@synthesize circuitLength;

- (NSUInteger) getCircuitLength {
    return self.nodes.count;
}

- (void) setCircuitLength:(NSUInteger)newLength {
    if (newLength == needLength || self.isBusy) {
        return;
    }

    needLength = newLength;

    if (needLength == 0) {
        [self close];
    }

    if (self.circuitLength < needLength) {
        [self extend];
    }
    else {
        [self trancate];
    }
}

@synthesize tailNodeIndex;

- (NSUInteger) getTailNodeIndex {
    return self.nodes.count - 1;
}

@synthesize directoryNodeIndex = _directoryNodeIndex;

- (NSInteger) getDirectoryNodeIndex {
    @synchronized(self) {
        if (_directoryNodeIndex == -1) {
            for (NSInteger i = self.nodes.count - 1; i >= 0 && _directoryNodeIndex == -1; i--) {
                NSMutableDictionary *torCtx = [self.nodes objectAtIndex:i];
                // last node is circuit might be not be ready yet
                if ([torCtx objectForKey:kOPCircuitNodeReadyKey] != NULL) {
                    OPTorNode *node = [torCtx objectForKey:kOPCircuitNodeKey];
                    if (node.isV2Dir) {
                        _directoryNodeIndex = i;
                    }
                }
            }
        }
    }
    return _directoryNodeIndex;
}

@synthesize isDirectoryServiceAvailable;

- (BOOL) getIsDirectoryServiceAvailable {
    return self.directoryNodeIndex >= 0;
}

- (BOOL) canExitToPort:(uint16)port {
    NSMutableDictionary *lastNodeCtx = [self.nodes lastObject];
    OPTorNode *node = [lastNodeCtx objectForKey:kOPCircuitNodeKey];
    if (node) {
        return [node canExitToPort:port];
    }
    return NO;
}

- (NSData *) handshakeRequestData {

    if (self.nodes == NULL || self.nodes.count == 0) {
        [self logMsg:@"Internal failure. Requested for handshake with undefined node or with node which has no descriptor loaded"];
        return NULL;
    }

    [self logMsg:@"Handshake begin"];

    // TAP handshake
    // PK-encrypted:
    //    Padding                       [PK_PAD_LEN bytes]
    //    Symmetric key                 [KEY_LEN bytes]
    //    First part of g^x             [PK_ENC_LEN-PK_PAD_LEN-KEY_LEN bytes]
    // Symmetrically encrypted:
    //    Second part of g^x            [DH_LEN-(PK_ENC_LEN-PK_PAD_LEN-KEY_LEN) bytes]

    //    NSMutableDictionary *lastNodeCtx = [self.nodes objectAtIndex:self.nodes.count - 1];
    NSMutableDictionary *lastNodeCtx = [self.nodes lastObject];

    OPTorNode *node = [lastNodeCtx objectForKey:kOPCircuitNodeKey];
    OPDiffieHellman *dh = [[OPDiffieHellman alloc] init];
    OPSimmetricKey *simmetricKey = [[OPSimmetricKey alloc] init];

    NSData *dhRequest = dh.request;
    NSUInteger dhPart1Len = node.onionKey.keyLength - node.onionKey.padLength - simmetricKey.keyLength;

    NSMutableData *payloadPart1Clear = [NSMutableData dataWithCapacity:simmetricKey.keyData.length + dhPart1Len];
    [payloadPart1Clear appendData:simmetricKey.keyData];
    [payloadPart1Clear appendBytes:dhRequest.bytes length:dhPart1Len];
    NSMutableData *payloadPart2Clear = [NSMutableData dataWithBytes:dhRequest.bytes + dhPart1Len length:dhRequest.length - dhPart1Len];
    
    NSMutableData *handshakeDada = [NSMutableData data];
    [handshakeDada appendData:[node.onionKey encryptData:payloadPart1Clear]];
    [handshakeDada appendData:[simmetricKey encryptData:payloadPart2Clear]];
    
    [simmetricKey release];

    [lastNodeCtx setObject:dh forKey:kOPCircuitHandshakeKey];
    [dh release];

    return handshakeDada;
}

- (BOOL) handshakeFinishWithResponseData:(NSData *)data {
    
    if (!data || data.length <  dhPublicKeyLen + sha1DigestLen) {
        [self logMsg:@"Handshake response is too short"];
        return NO;
    }

    if (self.nodes == NULL || self.nodes.count == 0) {
        return NO;
    }

    // DH public key
    // sha1 hash of shared DH key
    
    BOOL result = YES;

    //    NSMutableDictionary *lastNodeCtx = [self.nodes objectAtIndex:self.nodes.count - 1];
    NSMutableDictionary *lastNodeCtx = [self.nodes lastObject];

    OPDiffieHellman *dh = [lastNodeCtx objectForKey:kOPCircuitHandshakeKey];
    NSData *dhSharedKey = [dh deriveSimmetricKeyDataWithResonse:[NSData dataWithBytes:data.bytes length:dhPublicKeyLen]];
    NSMutableData *baseMaterial = [NSMutableData dataWithData:dhSharedKey];
    [baseMaterial setLength:baseMaterial.length + 1];
    
    NSMutableData *keys = [NSMutableData dataWithCapacity:sha1DigestLen * 2];
    
    for (uint8 i = 0; result && i < 5; i++) {
        ((uint8 *)baseMaterial.mutableBytes)[baseMaterial.length - 1] = i;
        //[self logMsg:@"baseMaterial:%@", baseMaterial];
        switch (i) {
            case 0: { // check if key has been learned correctly
                NSData *sha1Local = [OPSHA1 digestOfData:baseMaterial];
                NSData *sha1Remote = [NSData dataWithBytes:data.bytes + dhPublicKeyLen length:sha1DigestLen];
                //[self logMsg:@"KH:%@",sha1Remote];
                if (![sha1Local isEqualToData:sha1Remote]) {
                    [self logMsg:@"Handshake digest missmatch"];
                    result = NO;
                }
            } break;
            
            case 1: { // forward digest Df;
                OPSHA1 *df = [[OPSHA1 alloc] init];
                [df updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                //[df updateWithData:baseMaterial];
                [lastNodeCtx setObject:df forKey:kOPCircuitForwardDigestKey];
                [df release];
            } break;
                
            case 2: { // backward digest Db;
                OPSHA1 *db = [[OPSHA1 alloc] init];
                [db updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                //[db updateWithData:baseMaterial];
                [lastNodeCtx setObject:db forKey:kOPCircuitBackwardDigestKey];
                [db release];
            } break;
                
            case 3: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
            } break;
                
            case 4: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
                //[self logMsg:@"Keys material:%@", keys];
                
                OPSimmetricKey *kf = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes length:16]];
                [lastNodeCtx setObject:kf forKey:kOPCircuitForwardSimmetricKeyKey];
                [kf release];
                
                OPSimmetricKey *kb = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes + 16 length:16]];
                [lastNodeCtx setObject:kb forKey:kOPCircuitBackwardSimmetricKeyKey];
                [kb release];
            } break;
        }
    }

    [lastNodeCtx removeObjectForKey:kOPCircuitHandshakeKey];
    [self logMsg:@"Handshake complete"];

    return result;
}

- (void) relayCommand:(OPRelayCommand)command toNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data {
    [self logMsg:@"relay command: %i for stream: %i", command, streamId];

    // this is not needed
    if (nodeIndex >= self.nodes.count) {
        return;
    }
    
    NSMutableData *cellData = [[NSMutableData alloc] initWithCapacity:OPCellPayloadLen];
    [cellData setLength:sizeof(OPRelayCellPayload)];
    OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;
    cell->relayCommand = command;
    cell->recognized = 0;
    cell->streamId = CFSwapInt16HostToBig(streamId);
    cell->digest = 0;
    uint16 dataLen = (uint16)[data length];
    cell->length = CFSwapInt16HostToBig(dataLen);
    [cellData appendData:data];
    [cellData setLength:OPCellPayloadLen];
    
    NSDictionary *destRouter = [self.nodes objectAtIndex:nodeIndex];

    // update forwardDigest
    OPSHA1 *digest = [destRouter objectForKey:kOPCircuitForwardDigestKey];
    [digest updateWithData:cellData];
    NSData *interimDigest = [digest digest];
    memcpy(&cell->digest, interimDigest.bytes, sizeof(cell->digest));
    
    // encrypt
    for (NSInteger i = nodeIndex; i >= 0; i--) {
        OPSimmetricKey *key = [self.nodes[i] objectForKey:kOPCircuitForwardSimmetricKeyKey];
        [key inplaceEncryptData:cellData];
    }
    
    if (command == OPRelayCommandExtend) {
        // [Starting with Tor 0.2.3.11-alpha, future version of Tor, relays should
        // reject any EXTEND cell not received in a RELAY_EARLY cell.]
        // TODO: check if version is greater or equal to mentioned above
        [self.connection sendCommand:OPConnectionCommandRelayEarly withData:cellData];
    }
    else {
        [self.connection sendCommand:OPConnectionCommandRelay withData:cellData];
    }

    [cellData release];
}

- (void) processCommand:(OPRelayCommand)command fromNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data {
    switch (command) {
        case OPRelayCommandExtended: {
            [self extendFinishWithResult:[self handshakeFinishWithResponseData:data]];
        } break;

        case OPRelayCommandConnected: {
            NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];
            [streamCtx setObject:[NSNumber numberWithBool:YES] forKey:kOPStreamIsConnectedKey];
            id<OPCircuitStreamDelegate> delegate = [streamCtx objectForKey:kOPStreamDelegateKey];
            [delegate streamOpened];
        } break;

        case OPRelayCommandEnd: {
            NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];
            [streamCtx setObject:[NSNumber numberWithBool:NO] forKey:kOPStreamIsConnectedKey];
            [self closeStream:streamId];
        } break;

        case OPRelayCommandRelay: {
            NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];
            id<OPCircuitStreamDelegate> delegate = [streamCtx objectForKey:kOPStreamDelegateKey];
            [delegate streamDidReceiveData:data];
        } break;

        case OPRelayCommandTruncated: {
            [self.delegate circuit:self event:OPCircuitEventTruncated];
            while (self.nodes.count > needLength) {
                [self.nodes removeLastObject];
            }

            NSSet *deadStreams = [self.streams keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                NSDictionary *stream = (NSDictionary *)obj;
                NSNumber *streamExitIndex = [stream objectForKey:kOPStreamExitNodeIndex];
                return ([streamExitIndex integerValue] >= self.circuitLength);
            }];

            [deadStreams enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                NSDictionary *stream = [self.streams objectForKey:obj];
                id<OPCircuitStreamDelegate> streamDelegate = [stream objectForKey:kOPStreamDelegateKey];
                [streamDelegate streamClosed];
                [self.streams removeObjectForKey:obj];
            }];

            self.isBusy = NO;
        } break;

        default: {
            [self logMsg:@"Not implemented 'Relay' command: %i",command];
        } break;
    }
}

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data {
    switch (command) {
        case OPConnectionCommandRelay: {
            NSMutableData *cellData = [NSMutableData dataWithBytes:[data bytes] length:[data length]];
            OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;
            // decrypt, Stop if recognized=0 and hash is correct.
            BOOL isRecognized = NO;
            for (NSInteger i = 0; !isRecognized && i < self.nodes.count; i++) {
                OPSimmetricKey *bKey = [self.nodes[i] objectForKey:kOPCircuitBackwardSimmetricKeyKey];

                // the next can happen if some error appears during extention process when last node does not have keys and digest setup yet
                if (bKey == NULL) {
                    [self logMsg:@"Failure while parsing relay cell (1)"];
                    break;
                }

                [bKey inplaceDecryptData:cellData];

                if (cell->recognized == 0) {
                    OPSHA1 *bDigest = [self.nodes[i] objectForKey:kOPCircuitBackwardDigestKey];
                    OPSHA1 *bDigestTemp = [bDigest copy];

                    uint32 digestReceived = cell->digest;
                    cell->digest = 0;

                    // calc hash
                    [bDigestTemp updateWithData:cellData];
                    NSData *cellDigestExpectedData = [bDigestTemp digest];
                    uint32 cellDigestExpected;
                    memcpy(&cellDigestExpected, cellDigestExpectedData.bytes, sizeof(uint32));

                    if (digestReceived == cellDigestExpected) {
                        //[self logMsg:@"CELL RECOGNIZED"];
                        [self.nodes[i] setObject:bDigestTemp forKey:kOPCircuitBackwardDigestKey];
                        isRecognized = YES;

                        [self processCommand:cell->relayCommand
                                    fromNode:i
                                   forStream:CFSwapInt16BigToHost(cell->streamId)
                                    withData:[NSData dataWithBytes:cell->payload length:CFSwapInt16BigToHost(cell->length)]
                         ];
                    }
                    else {
                        cell->digest = digestReceived;
                    }

                    [bDigestTemp release];
                }
            }

            if (!isRecognized) {
                [self logMsg:@"Non recognized cell. Terminating..."];
                [self close];
            }

        } break;

        case OPConnectionCommandCreated: {
            NSMutableDictionary *firstTor = [self.nodes objectAtIndex:0];
            NSNumber *command = [firstTor objectForKey:kOPCircuitNodeSentCommand];
            if ([command intValue] == OPConnectionCommandCreate) {
                [firstTor removeObjectForKey:kOPCircuitNodeSentCommand];
                [self extendFinishWithResult:[self handshakeFinishWithResponseData:data]];
            }
            else {
                [self logMsg:@"Unexpected 'Created' cell received (WTF ???). Terminating connection"];
                [self close];
            }
        } break;

        case OPConnectionCommandDestroy: {
            [self logMsg:@"'Destroy' cell received. Terminating connection"];
            [self close];
            if (data.length >= 1) {
                uint8_t reason = ((uint8_t *)data.bytes)[0];
                [self logMsg:@"Destroy reason: %i", reason];
            }
            else {
                [self logMsg:@"Destroy cell contains no data"];
            }
        } break;

        default: {
            [self logMsg:@"OPConnectionCommand %i", command];
        } break;
    }
}

- (void) connection:(OPConnection *)sender onEvent:(OPConnectionEvent)event {
    switch (event) {
        case OPConnectionEventConnected: {
            [self logMsg:@"OPConnectionEventConnected"];

            NSMutableDictionary *firstTor = [self.nodes objectAtIndex:0];
            [firstTor setObject:[NSNumber numberWithInt:OPConnectionCommandCreate] forKey:kOPCircuitNodeSentCommand];
            [self.connection sendCommand:OPConnectionCommandCreate withData:[self handshakeRequestData]];
            OPTorNode *node = (OPTorNode *)[firstTor objectForKey:kOPCircuitNodeKey];
            [node releaseDescriptor];
        } break;
        
        case OPConnectionEventConnectionFailed: {
            [self logMsg:@"OPConnectionEventConnectionFailed"];
            [self close];
        } break;
            
        case OPConnectionEventDisconnected: {
            [self logMsg:@"OPConnectionEventDisconnected"];
            [self close];
        } break;            
    }
}

- (BOOL) canExtend {
    return self.circuitLength < [OPConfig config].maxCircuitLength;
}

- (BOOL) canExtendTo:(OPTorNode *)node {
    if ([self canExtend]) {
        if (self.circuitLength > 1) {
            NSMutableDictionary *ctx = [self.nodes objectAtIndex:self.circuitLength - 1];
            OPTorNode *n = (OPTorNode *)[ctx objectForKey:kOPCircuitNodeKey];
            if ([n isEqualTo:node]) {
                return NO;
            }
        }
        if (self.circuitLength > 2) {
            NSMutableDictionary *ctx = [self.nodes objectAtIndex:self.circuitLength - 2];
            OPTorNode *n = (OPTorNode *)[ctx objectForKey:kOPCircuitNodeKey];
            if ([n isEqualTo:node]) {
                return NO;
            }
        }
        return YES;
    }
    return NO;
}

- (void) extendToNode:(OPTorNode *)node {
    if (![self canExtendTo:node]) {
        [self.delegate circuit:self event:OPCircuitEventExtentionNotPossible];
        return;
    }
    [self.nodes addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:node, kOPCircuitNodeKey, nil]];
    if (self.circuitLength == 1) {
        [node retainDescriptor];
        [self.connection connectToNode:node];
    }
    else {
        NSMutableDictionary *lastNodeCtx = [self.nodes lastObject];
        OPTorNode *nextNode = [lastNodeCtx objectForKey:kOPCircuitNodeKey];

        uint32_t ip = nextNode.ip;
        uint16_t port = CFSwapInt16HostToBig(nextNode.orPort);
        NSData *handshake = [self handshakeRequestData];
        NSData *identDigest = nextNode.identKey.digest;

        NSMutableData *extendData = [NSMutableData dataWithCapacity:26 + handshake.length];
        [extendData appendBytes:&ip length:4];
        [extendData appendBytes:&port length:2];
        [extendData appendData:handshake];
        [extendData appendData:identDigest];

        [self relayCommand:OPRelayCommandExtend toNode:self.nodes.count - 2 forStream:0 withData:extendData];
    }
}

- (void) extend {
    if (self.circuitLength >= needLength) {
        [self.delegate circuit:self event:OPCircuitEventExtended];
        self.isBusy = NO;
        return;
    }

    [[OPTorDirectory directory] getRandomRouterAsync:^(OPTorNode *node) {
        [self extendToNode:node];
    }];
}

- (void) extendFinishWithResult:(BOOL)result {
    if (result) {
        NSMutableDictionary *lastNodeCtx = [self.nodes lastObject];
        [lastNodeCtx setValue:[NSNumber numberWithBool:YES] forKey:kOPCircuitNodeReadyKey];
        [self logMsg:@"Circuit extended. current len:%lu", (unsigned long)self.circuitLength];
    }
    else {
        [self logMsg:@"Circuit extention failed"];
        [self.nodes removeObjectAtIndex:self.circuitLength - 1];
    }
    [self extend];
}

- (void) trancate {
    if (needLength >= self.circuitLength) {
        return;
    }

    if (needLength < _directoryNodeIndex) {
        _directoryNodeIndex = -1;
    }

    if (needLength > 0) {
        [self relayCommand:OPRelayCommandTruncate toNode:needLength - 1 forStream:0 withData:NULL];
        return;
    }

    [self close];
}

- (void) appendNode:(OPTorNode *)node {
    if (node || !self.isBusy) {
        needLength = self.circuitLength + 1;
        [self extendToNode:node];
    }
}

- (void) close {

    NSArray *openedStreams = [self.streams allKeys];

    for (NSNumber *key in openedStreams) {
        OPStreamId streamId = [key integerValue];
        [self closeStream:streamId];
    }

    [self.connection disconnect];

    [self.streams removeAllObjects];
    [self.nodes removeAllObjects];
    [self.delegate circuit:self event:OPCircuitEventClosed];
}

- (OPStreamId) addEmptyStreamCtx {

    OPStreamId nextId = streamIdCounter + arc4random() % 3;
    if (nextId == 0) {
        nextId++;
    }
    streamIdCounter = nextId;

    NSMutableDictionary *streamCtx = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithBool:NO], kOPStreamIsConnectedKey,
                                      nil];
    @synchronized(self.streams) {
        [self.streams setObject:streamCtx forKey:[NSNumber numberWithInt:nextId]];
    }

    return nextId;
}

- (NSMutableDictionary *) getStreamCtxWithStreamId:(OPStreamId)streamId {
    @synchronized(self.streams) {
        NSMutableDictionary *streamCtx = [self.streams objectForKey:[NSNumber numberWithInt:streamId]];
        return [[streamCtx retain] autorelease];
    }
}

- (void) removeStreamCtxWithStreamId:(OPStreamId)streamId {
    @synchronized(self.streams) {
        [self.streams removeObjectForKey:[NSNumber numberWithInt:streamId]];
    }
}

- (OPStreamId) openDirectoryStreamWithDelegate:(id<OPCircuitStreamDelegate>)delegate {
    if (!self.isDirectoryServiceAvailable) {
        return 0;
    }

    OPStreamId streamId = [self addEmptyStreamCtx];
    NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];

    [streamCtx setObject:delegate forKey:kOPStreamDelegateKey];
    [streamCtx setObject:[NSNumber numberWithInteger:self.directoryNodeIndex] forKey:kOPStreamExitNodeIndex];

    [self relayCommand:OPRelayCommandBeginDir toNode:self.directoryNodeIndex forStream:streamId withData:NULL];

    return streamId;
}

- (void) closeStream:(OPStreamId)streamId {
    NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];
    if (streamCtx == NULL) {
        return;
    }

    NSNumber *isConnected = [streamCtx objectForKey:kOPStreamIsConnectedKey];
    if ([isConnected boolValue] == YES) {
        NSNumber *nodeIndex = [streamCtx objectForKey:kOPStreamExitNodeIndex];
        [self relayCommand:OPRelayCommandEnd toNode:[nodeIndex integerValue] forStream:streamId withData:NULL];
    }

    id<OPCircuitStreamDelegate> streamDelegate = [streamCtx objectForKey:kOPStreamDelegateKey];
    [streamDelegate streamClosed];

    [self removeStreamCtxWithStreamId:streamId];
}

- (void) sendData:(NSData *)data overStream:(OPStreamId)streamId {
    if (data == NULL) {
        return;

    }

    NSMutableDictionary *streamCtx = [self getStreamCtxWithStreamId:streamId];
    if (streamCtx == NULL) {
        return;
    }

    NSNumber *exitIndex = [streamCtx objectForKey:kOPStreamExitNodeIndex];
    [self relayCommand:OPRelayCommandRelay toNode:[exitIndex integerValue] forStream:streamId withData:data];
}


- (id) initWithDelegate:(id<OPCircuitDelegate>)delegate {
    [self logMsg:@"INIT CIRCUIT"];
    self = [super init];
    if (self) {
        self.delegate = delegate;
        streamIdCounter = 1;
        self.streams = [NSMutableDictionary dictionaryWithCapacity:10];
        self.nodes = [NSMutableArray arrayWithCapacity:[OPConfig config].maxCircuitLength];
        self.connection = [OPConnection connectionWithDelegate:self];
        self.isBusy = NO;
        _directoryNodeIndex = -1;
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC CIRCUIT"];
    [self close]; // important!!! needed to close streams as they retain its delegate.
    self.connection = NULL;
    self.nodes = NULL;
    self.streams = NULL;
    
    [super dealloc];
}

@end
