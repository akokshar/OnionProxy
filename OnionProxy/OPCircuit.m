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
    OPRelayCommanBegin = 1,     // RELAY_BEGIN     [forward]
    OPRelayCommanRelay = 2,     // RELAY_DATA      [forward or backward]
    OPRelayCommanEnd = 3,       // RELAY_END       [forward or backward]
    OPRelayCommanConnected = 4, // RELAY_CONNECTED [backward]
    OPRelayCommanSendMe = 5,    // RELAY_SENDME    [forward or backward] [sometimes control]
    OPRelayCommanExtend = 6,    // RELAY_EXTEND    [forward]             [control]
    OPRelayCommanExtended = 7,  // RELAY_EXTENDED  [backward]            [control]
    OPRelayCommanTruncate = 8,  // RELAY_TRUNCATE  [forward]             [control]
    OPRelayCommanTruncated = 9, // RELAY_TRUNCATED [backward]            [control]
    OPRelayCommanDrop = 10,     // RELAY_DROP      [forward or backward] [control]
    OPRelayCommanResolve = 11,  // RELAY_RESOLVE   [forward]
    OPRelayCommanResolved = 12, // RELAY_RESOLVED  [backward]
    OPRelayCommanBeginDir = 13, // RELAY_BEGIN_DIR [forward]
    OPRelayCommanExtend2 = 14,  // RELAY_EXTEND2   [forward]             [control]
    OPRelayCommanExtended2 = 15 // RELAY_EXTENDED2 [backward]            [control]
    //32..40 -- Used for hidden services; see rend-spec.txt.
} OPRelayCommand;

#pragma pack(1)
typedef struct {
    uint8 relayCommand;
    uint16 recognized;
    StreamId streamId;
    uint32 digest;
    uint16 length;
    uint8 payload[];
} OPRelayCellPayload;
#pragma pack()

NSString * const kOPCircuitNodeKey = @"NodeKey";
NSString * const kOPCircuitHandshakeKey = @"HandshakeKey";
NSString * const kOPCircuitForwardDigestKey = @"ForwardDigestKey";
NSString * const kOPCircuitBackwardDigestKey = @"BackwardDigestKey";
NSString * const kOPCircuitForwardSimmetricKeyKey = @"ForwardSimmetricKeyKey";
NSString * const kOPCircuitBackwardSimmetricKeyKey = @"BackwardSimmetricKeyKey";
NSString * const kOPCircuitNodeSentCommand = @"SentCommand";

NSString * const kOPStreamClientKey = @"ClientKey";
NSString * const kOPStreamIsConnectedKey = @"IsConnectedKey";

@interface OPCircuit() {
    //BOOL isBusy;
    StreamId streamIdCounter;
}

@property (retain) OPConnection *connection;
@property (retain) NSMutableArray *nodes;
@property (retain) NSMutableDictionary *streams;

- (StreamId) generateStreamId;

/**
 *  return handshake data to be sent to the last router
 */
- (NSData *) handshakeRequestData;

/**
 *  Finish handshake with the last router, setup keys and digests
 */
- (BOOL) handshakeFinishWithResponseData:(NSData *)data;

/**
 *  return extend command payload to be sent to the last router
 */
- (NSData *) extendRequestData;

/**
 * Finish extention with the last router, setup keys and digests
 */
- (BOOL) extendFinishWithResponseData:(NSData *)data;

- (void) relayCommand:(OPRelayCommand)command toNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data;
- (void) processCommand:(OPRelayCommand)command fromNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data;

@end

@implementation OPCircuit

@synthesize length;

- (NSUInteger) getLength {
    return self.nodes.count;
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

    NSMutableDictionary *lastTor = [self.nodes objectAtIndex:self.nodes.count - 1];

    OPTorNode *node = [lastTor objectForKey:kOPCircuitNodeKey];
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

    [lastTor setObject:dh forKey:kOPCircuitHandshakeKey];
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

    NSMutableDictionary *lastTor = [self.nodes objectAtIndex:self.nodes.count - 1];

    OPDiffieHellman *dh = [lastTor objectForKey:kOPCircuitHandshakeKey];
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
                [lastTor setObject:df forKey:kOPCircuitForwardDigestKey];
                [df release];
            } break;
                
            case 2: { // backward digest Db;
                OPSHA1 *db = [[OPSHA1 alloc] init];
                [db updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                //[db updateWithData:baseMaterial];
                [lastTor setObject:db forKey:kOPCircuitBackwardDigestKey];
                [db release];
            } break;
                
            case 3: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
            } break;
                
            case 4: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
                //[self logMsg:@"Keys material:%@", keys];
                
                OPSimmetricKey *kf = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes length:16]];
                [lastTor setObject:kf forKey:kOPCircuitForwardSimmetricKeyKey];
                [kf release];
                
                OPSimmetricKey *kb = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes + 16 length:16]];
                [lastTor setObject:kb forKey:kOPCircuitBackwardSimmetricKeyKey];
                [kb release];
            } break;
        }
    }

    [lastTor removeObjectForKey:kOPCircuitHandshakeKey];
    [self logMsg:@"Handshake complete"];

    return result;
}

- (NSData *) extendRequestData {
    [self logMsg:@"Extention begin"];
    
    NSMutableDictionary *lastTor = [self.nodes objectAtIndex:self.nodes.count - 1];

    OPTorNode *nextNode = [lastTor objectForKey:kOPCircuitNodeKey];

    uint32_t ip = nextNode.ip;
    uint16_t port = CFSwapInt16HostToBig(nextNode.orPort);
    NSData *handshake = [self handshakeRequestData];
    NSData *identDigest = nextNode.identKey.digest;
    
    NSMutableData *extendData = [NSMutableData dataWithCapacity:26 + handshake.length];
    [extendData appendBytes:&ip length:4];
    [extendData appendBytes:&port length:2];
    [extendData appendData:handshake];
    [extendData appendData:identDigest];

    return extendData;
}

- (BOOL) extendFinishWithResponseData:(NSData *)data {
    if ([self handshakeFinishWithResponseData:data] ) {
        [self logMsg:@"Extention complete"];
        return YES;
    }
    [self logMsg:@"Extention failed"];
    return NO;
}

- (void) relayCommand:(OPRelayCommand)command toNode:(NSUInteger)nodeIndex forStream:(uint16_t)streamId withData:(NSData *)data {
    // this check is not needed
    if (data == NULL) {
        return;
    }

    // this is not needed as well
    if (nodeIndex >= self.nodes.count) {
        return;
    }
    
    NSMutableData *cellData = [[NSMutableData alloc] initWithCapacity:509];
    [cellData setLength:sizeof(OPRelayCellPayload)];
    OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;
    cell->relayCommand = command;
    cell->recognized = 0;
    cell->streamId = CFSwapInt16HostToBig(streamId);
    cell->digest = 0;
    uint16 dataLen = (uint16)[data length];
    cell->length = CFSwapInt16HostToBig(dataLen);
    [cellData appendData:data];
    [cellData setLength:509];
    
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
    
    if (command == OPRelayCommanExtend) {
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
        case OPRelayCommanExtended: {
            if ([self extendFinishWithResponseData:data]) {
                [self logMsg:@"Circuit extended. current len:%lu", (unsigned long)self.length];
                [self.delegate circuit:self event:OPCircuitEventExtended];
            }
            else {
                [self.nodes removeObjectAtIndex:self.nodes.count - 1];
                [self.delegate circuit:self event:OPCircuitEventExtentionFailed];
            }
        } break;

        default:
            break;
    }
}

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data {
    switch (command) {
        case OPConnectionCommandRelay: {
            NSMutableData *cellData = [NSMutableData dataWithBytes:data.bytes length:data.length];
            // decrypt, Stop if recognized=0 and hash is correct.
            BOOL isRecognized = NO;
            for (NSInteger i = 0; !isRecognized && i < self.nodes.count; i++) {
                OPSimmetricKey *bKey = [self.nodes[i] objectForKey:kOPCircuitBackwardSimmetricKeyKey];
                [bKey inplaceDecryptData:cellData];
                OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;

                if (cell->recognized == 0) {
                    OPSHA1 *bDigest = [self.nodes[i] objectForKey:kOPCircuitBackwardDigestKey];
                    uint32 digestReceived = cell->digest;
                    OPSHA1 *bDigestTemp = [bDigest copy];

                    // calc hash
                    cell->digest = 0;
                    [bDigestTemp updateWithData:cellData];
                    NSData *cellDigestData = [bDigestTemp digest];
                    uint32 cellDigest;
                    memcpy(&cellDigest, cellDigestData.bytes, sizeof(uint32));

                    [bDigestTemp release];
                    cell->digest = digestReceived;

                    //[self logMsg:@"%i:%i", cellDigest, cell->digest];
                    if (cellDigest == cell->digest) {
                        //[self logMsg:@"CELL RECOGNIZED"];
                        [bDigest updateWithData:cellData];
                        isRecognized = YES;

                        [self processCommand:cell->relayCommand
                                    fromNode:i
                                   forStream:CFSwapInt16BigToHost(cell->streamId)
                                    withData:[NSData dataWithBytes:cell->payload length:CFSwapInt16BigToHost(cell->length)]
                         ];
                    }
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

                if ([self handshakeFinishWithResponseData:data]) {
                    [self logMsg:@"Circuit created"];
                    [self.delegate circuit:self event:OPCircuitEventExtended];
                }
                else {
                    [self logMsg:@"Handshake failed. Terminating connection"];
                    [self.delegate circuit:self event:OPCircuitEventExtentionFailed];
                    [self close];
                }
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
            [self.delegate circuit:self event:OPCircuitEventConnected];

            NSMutableDictionary *firstTor = [self.nodes objectAtIndex:0];
            [firstTor setObject:[NSNumber numberWithInt:OPConnectionCommandCreate] forKey:kOPCircuitNodeSentCommand];
            [sender sendCommand:OPConnectionCommandCreate withData:[self handshakeRequestData]];
        } break;
        
        case OPConnectionEventConnectionFailed: {
            [self logMsg:@"OPConnectionEventConnectionFailed"];
            [self.delegate circuit:self event:OPCircuitEventConnectionFailed];
        } break;
            
        case OPConnectionEventDisconnected: {
            [self logMsg:@"OPConnectionEventDisconnected"];
            [self.delegate circuit:self event:OPCircuitEventDisconnected];
        } break;            
    }
}

- (BOOL) extentTo:(OPTorNode *)node {
    if (!node) {
        return NO;
    }

    if (node.onionKey == NULL) {
        [self logMsg:@"Circuit extention is not possible - next node contains no onionKey"];
        return NO;
    }

    [self.nodes addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:node, kOPCircuitNodeKey, nil]];
    if (self.length == 1) {
        [self.connection connectToNode:node];
    }
    else {
        [self relayCommand:OPRelayCommanExtend toNode:self.nodes.count - 2 forStream:0 withData:[self extendRequestData]];
    }
    return YES;
}

- (void) close {
    [self.connection disconnect];
    [self.nodes removeAllObjects];
    [self.delegate circuit:self event:OPCircuitEventClosed];
}

- (StreamId) generateStreamId {
    return streamIdCounter++;
}

- (StreamId) addStreamForClient:(id<OPStreamDelegate>)client {
    StreamId streamId = [self generateStreamId];
    NSMutableDictionary *stream = [NSMutableDictionary dictionaryWithObject:client forKey:kOPStreamClientKey];
    [self.streams setObject:stream forKey:[NSNumber numberWithInt:streamId]];
    return streamId;
}

- (void) removeStreamWithStreamId:(StreamId)streamId {
    [self.streams removeObjectForKey:[NSNumber numberWithInt:streamId]];
}

- (void) connectStreamWithStreamId:(StreamId)streamId toHostWithName:(NSString *)host port:(NSUInteger)port {

}

- (id) initWithDelegate:(id<OPCircuitDelegate>)delegate {
    [self logMsg:@"INIT CIRCUIT"];
    self = [super init];
    if (self) {
        self.delegate = delegate;
        streamIdCounter = 1;
        self.streams = [NSMutableDictionary dictionaryWithCapacity:10];
        self.nodes = [NSMutableArray arrayWithCapacity:[OPConfig config].circuitLength];
        self.connection = [OPConnection connectionWithDelegate:self];
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC CIRCUIT"];
    self.connection = NULL;
    self.nodes = NULL;
    self.streams = NULL;
    
    [super dealloc];
}

@end
