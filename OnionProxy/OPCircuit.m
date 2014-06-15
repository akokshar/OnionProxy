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

NSString * const kOPCircuitNodeKey = @"NodeKey";
NSString * const kOPCircuitHandshakeKey = @"HandshakeKey";
NSString * const kOPCircuitForwardDigestKey = @"ForwardDigestKey";
NSString * const kOPCircuitBackwardDigestKey = @"BackwardDigestKey";
NSString * const kOPCircuitForwardSimmetricKeyKey = @"ForwardSimmetricKeyKey";
NSString * const kOPCircuitBackwardSimmetricKeyKey = @"BackwardSimmetricKeyKey";

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
    uint16 streamId;
    uint32 digest;
    uint16 length;
    uint8 payload[];
} OPRelayCellPayload;
#pragma pack()

@interface OPCircuit() {
    NSMutableArray *nodes;
    OPConnection *connection;
}

@property (getter = getNextHop, setter = setNextHop:) NSMutableDictionary *nextHop;

- (NSData *) handshakeRequestData;
- (BOOL) handshakeFinishWithResponseData:(NSData *)data;
- (NSData *) extendRequestData;
- (BOOL) extendFinishWithResponseData:(NSData *)data;
- (void) relayCommand:(OPRelayCommand)command forStream:(uint16_t)streamId withData:(NSData *)data;

- (void) establishWithDestinationPort:(NSUInteger)port;

@end

@implementation OPCircuit

@synthesize length;

- (NSUInteger) getLength {
    return nodes.count;
}

@synthesize nextHop = _nextHop;

- (NSMutableDictionary *) getNextHop {
    @synchronized(self) {
        if (_nextHop == NULL) {
            OPTorNode *node = [[OPTorDirectory directory] getRandomRouter];
            
            if (!node.isHasLastDescriptor) {
                [self logMsg:@"selected node is not yet ready. wait for a while"];
                sleep(2);
            }
            if (node) {
                _nextHop = [[NSMutableDictionary alloc] initWithObjectsAndKeys:node, kOPCircuitNodeKey, nil];
            }
        }
    }
    return _nextHop;
}

- (void) setNextHop:(NSMutableDictionary *)nextHop {
    @synchronized(self) {
        if (_nextHop) {
            [_nextHop release];
        }
        _nextHop = nextHop;
    }
}

/**
 *  return handshake data to be sent to a nextHop
 */

- (NSData *) handshakeRequestData {
    
    if (self.nextHop == NULL) {
        return NULL;
    }

    // TAP handshake
    // PK-encrypted:
    //    Padding                       [PK_PAD_LEN bytes]
    //    Symmetric key                 [KEY_LEN bytes]
    //    First part of g^x             [PK_ENC_LEN-PK_PAD_LEN-KEY_LEN bytes]
    // Symmetrically encrypted:
    //    Second part of g^x            [DH_LEN-(PK_ENC_LEN-PK_PAD_LEN-KEY_LEN) bytes]
    
    OPTorNode *node = [self.nextHop objectForKey:kOPCircuitNodeKey];
    OPDiffieHellman *dh = [[OPDiffieHellman alloc] init];
    OPSimmetricKey *simmetricKey = [[OPSimmetricKey alloc] init];
    [self logMsg:@"simmetricKeyLen:%lu", (unsigned long)simmetricKey.keyData.length];
    
    NSData *dhRequest = dh.request;
    [self logMsg:@"DhRequestLen:%lu", (unsigned long)dhRequest.length];
    [self logMsg:@"node.onionKey.keyLength:%lu",(unsigned long)node.onionKey.keyLength];
    NSUInteger dhPart1Len = node.onionKey.keyLength - node.onionKey.padLength - simmetricKey.keyLength;
    [self logMsg:@"dhPart1:%lu", (unsigned long)dhPart1Len];
    
    NSMutableData *payloadPart1Clear = [NSMutableData dataWithCapacity:simmetricKey.keyData.length + dhPart1Len];
    [payloadPart1Clear appendData:simmetricKey.keyData];
    [payloadPart1Clear appendBytes:dhRequest.bytes length:dhPart1Len];
    NSMutableData *payloadPart2Clear = [NSMutableData dataWithBytes:dhRequest.bytes + dhPart1Len length:dhRequest.length - dhPart1Len];
    
    NSMutableData *handshakeDada = [NSMutableData data];
    [handshakeDada appendData:[node.onionKey encryptData:payloadPart1Clear]];
    [handshakeDada appendData:[simmetricKey encryptData:payloadPart2Clear]];
    
    [simmetricKey release];

    [self.nextHop setObject:dh forKey:kOPCircuitHandshakeKey];
    [dh release];

    return handshakeDada;
}

/**
 *  Finish handshake with a nextHop, setup keys and digests, add hop to a circuit if successful
 */

- (BOOL) handshakeFinishWithResponseData:(NSData *)data {
    
    if (!data || data.length <  dhPublicKeyLen + sha1DigestLen) {
        [self logMsg:@"Handshake response is too short"];
        self.nextHop = NULL;
        return NO;
    }

    // DH public key
    // sha1 hash of shared DH key
    
    BOOL result = YES;

    OPDiffieHellman *dh = [self.nextHop objectForKey:kOPCircuitHandshakeKey];

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
                    self.nextHop = NULL;
                    result = NO;
                }
            } break;
            
            case 1: { // forward digest Df;
                OPSHA1 *df = [[OPSHA1 alloc] init];
                [df updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                //[df updateWithData:baseMaterial];
                [self.nextHop setObject:df forKey:kOPCircuitForwardDigestKey];
                [df release];
            } break;
                
            case 2: { // backward digest Db;
                OPSHA1 *db = [[OPSHA1 alloc] init];
                [db updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                //[db updateWithData:baseMaterial];
                [self.nextHop setObject:db forKey:kOPCircuitBackwardDigestKey];
                [db release];
            } break;
                
            case 3: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
            } break;
                
            case 4: { // forward and backward keys
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
                //[self logMsg:@"Keys material:%@", keys];
                
                OPSimmetricKey *kf = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes length:16]];
                [self.nextHop setObject:kf forKey:kOPCircuitForwardSimmetricKeyKey];
                [kf release];
                
                OPSimmetricKey *kb = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes + 16 length:16]];
                [self.nextHop setObject:kb forKey:kOPCircuitBackwardSimmetricKeyKey];
                [kb release];
            }
        }
    }
    
    [self.nextHop removeObjectForKey:kOPCircuitHandshakeKey];
    [nodes addObject:self.nextHop];
    self.nextHop = NULL;
    
    return result;
}

/**
 *  return extend command payload to be sent to a last node in a circuit
 *  contains handshake request for a nextHop
 */

- (NSData *) extendRequestData {
    [self logMsg:@"extendRequestData"];
    
    // chose nextHop or exit if were not able to
    if (self.nextHop == NULL) {
        return NULL;
    }

    OPTorNode *nextNode = [self.nextHop objectForKey:kOPCircuitNodeKey];

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

/**
 * Finish handshake with a nextHop, setup keys and digests, add hop to a circuit if successful
 */

- (BOOL) extendFinishWithResponseData:(NSData *)data {
    [self logMsg:@"extendFinishWithResponseData"];

    return NO;
}

- (void) relayCommand:(OPRelayCommand)command forStream:(uint16_t)streamId withData:(NSData *)data {
    [self logMsg:@"relayCommand"];
    if (data == NULL) {
        return;
    }
    
    NSMutableData *cellData = [[NSMutableData alloc] initWithCapacity:509];
    [cellData setLength:sizeof(OPRelayCellPayload)];
    OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;
    cell->relayCommand = command;
    cell->recognized = 0;
    cell->streamId = CFSwapInt16HostToBig(streamId);
    cell->digest = 0;
    uint16 dataLen = (uint16)data.length;
    cell->length = CFSwapInt16HostToBig(dataLen);
    [cellData appendData:data];
    [cellData setLength:509];
    
    NSDictionary *lastHop = [nodes objectAtIndex:nodes.count - 1];
    if (lastHop != NULL) {
        // update forwardDigest
        OPSHA1 *digest = [lastHop objectForKey:kOPCircuitForwardDigestKey];
        [digest updateWithData:cellData];
        NSData *interimDigest = [digest digest];
        memcpy(&cell->digest, interimDigest.bytes, sizeof(cell->digest));
        
        // encrypt
        for (NSInteger i = nodes.count - 1; i >= 0; i--) {
            OPSimmetricKey *key = [nodes[i] objectForKey:kOPCircuitForwardSimmetricKeyKey];
            [key inplaceEncryptData:cellData];
        }
        
        //[Starting with Tor 0.2.3.11-alpha, future version of Tor, relays should
        // reject any EXTEND cell not received in a RELAY_EARLY cell.]
        if (command == OPRelayCommanExtend) { // TODO: check if version is greater or equal to mentioned above
            [connection sendCommand:OPConnectionCommandRelayEarly withData:cellData];
        }
        else {
            [connection sendCommand:OPConnectionCommandRelay withData:cellData];
        }
    }
    
    [cellData release];
}

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data {
    switch (command) {
        case OPConnectionCommandRelay: {
            NSMutableData *cellData = [NSMutableData dataWithData:data];
            // decrypt, Stop if recognized=0 and hash is correct.
            BOOL isRecognized = NO;
            for (NSInteger i = 0; !isRecognized && i < nodes.count; i++) {
                OPSHA1 *bDigest = [nodes[i] objectForKey:kOPCircuitBackwardDigestKey];
                OPSimmetricKey *bKey = [nodes[i] objectForKey:kOPCircuitBackwardSimmetricKeyKey];
                
                [bKey inplaceDecryptData:cellData];
                
                OPRelayCellPayload *cell = (OPRelayCellPayload *)cellData.mutableBytes;
                if (cell->recognized == 0) {
                    // calc hash
                    OPSHA1 *bDigestTemp = [bDigest copy];
                    uint32 digestReceived = cell->digest;
                    cell->digest = 0;
                    [bDigestTemp updateWithData:cellData];
                    NSData *cellDigestData = [bDigestTemp digest];
                    cell->digest = digestReceived;
                    [bDigestTemp release];
                    
                    uint32 cellDigest;
                    memcpy(&cellDigest, cellDigestData.bytes, sizeof(uint32));
                    
                    if (cellDigest == cell->digest) {
                        isRecognized = YES;
                    }
                }
                
                if (isRecognized) {
                    [bDigest updateWithData:cellData];
                    [self logMsg:@"CELL RECOGNIZED"];
                }
            }

        } break;
            
        case OPConnectionCommandCreated: {
            [self logMsg:@"OPConnectionCommandCreated"];

            if (![self handshakeFinishWithResponseData:data]) {
                [self logMsg:@"Handshake failed. Terminating connection"];
                [connection disconnect];
                return;
            }
            [self logMsg:@"HANDSHAKE SUCCESSFUL"];
            
            [self relayCommand:OPRelayCommanExtend forStream:0 withData:[self extendRequestData]];
        } break;

        case OPConnectionCommandDestroy: {
            uint8_t reason = ((uint8_t *)data.bytes)[0];
            [self logMsg:@"Destroy reason: %i", reason];
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
            [sender sendCommand:OPConnectionCommandCreate withData:[self handshakeRequestData]];
        } break;
        
        case OPConnectionEventConnectionFailed: {
            [self logMsg:@"OPConnectionEventConnectionFailed"];
        } break;
            
        case OPConnectionEventDisconnected: {
            [self logMsg:@"OPConnectionEventDisconnected"];
        } break;            
    }
}

- (void) establishWithDestinationPort:(NSUInteger)port {
    OPTorNode *entryNode = [self.nextHop objectForKey:kOPCircuitNodeKey];
    if (entryNode) {
        [connection connectToNode:entryNode];
        [self logMsg:@"Entry node onionKey %@", entryNode.onionKey];
        return;
    }
    [self logMsg:@"entry node is NULL"];
}

- (void) close {
    [connection disconnect];
    connection.delegate = NULL;
}

- (void) extentTo:(OPTorNode *)node {
    if (self.length == 0) {
        //connect
        self.nextHop = [[NSMutableDictionary alloc] initWithObjectsAndKeys:node, kOPCircuitNodeKey, nil];
        [connection connectToNode:node];
    }
    else {
        //extend
    }
}

- (id) init {
    [self logMsg:@"INIT CIRCUIT"];
    self = [super init];
    if (self) {
        connection = [[OPConnection alloc] init];
        nodes = [[NSMutableArray alloc] initWithCapacity:[OPConfig config].circuitLength];
        connection.delegate = self;
        //[self establishWithDestinationPort:80];
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC CIRCUIT"];
    [connection disconnect];
    [connection release];
    [nodes release];
    
    [super dealloc];
}

@end
