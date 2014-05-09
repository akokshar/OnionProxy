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
#import "OPConsensus.h"
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

typedef struct {
    
} OPClientHandshakeData;

typedef struct {
    char DHData[128];
    char KHData[20];
} OPServerHandshakeData;

@interface OPCircuit() {
    NSMutableArray *nodes;
    OPConnection *connection;
}

- (NSData *) beginHandshakeData;
- (BOOL) finishHandshakeWithResponseData:(NSData *)data;

- (void) addNode:(OPTorNode *)node;
- (void) establishWithDestinationPort:(NSUInteger)port;

@end

@implementation OPCircuit

/**
 *  return handshake data to be sent to a last node in a circuit
 */

- (NSData *) beginHandshakeData {

    // TAP handshake
    // PK-encrypted:
    //    Padding                       [PK_PAD_LEN bytes]
    //    Symmetric key                 [KEY_LEN bytes]
    //    First part of g^x             [PK_ENC_LEN-PK_PAD_LEN-KEY_LEN bytes]
    // Symmetrically encrypted:
    //    Second part of g^x            [DH_LEN-(PK_ENC_LEN-PK_PAD_LEN-KEY_LEN) bytes]
    
    NSMutableDictionary *hopParams = [nodes objectAtIndex:nodes.count - 1];
    OPTorNode *node = [hopParams objectForKey:kOPCircuitNodeKey];
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

    [hopParams setObject:dh forKey:kOPCircuitHandshakeKey];
    [dh release];

    return handshakeDada;
}

/**
 *  Finish handshake with a last node in circuit and setup keys and digests
 */

- (BOOL) finishHandshakeWithResponseData:(NSData *)data {
    
    if (data.length <  dhPublicKeyLen + sha1DigestLen) {
        [self logMsg:@"Handshake response is too short"];
        return NO;
    }

    // DH public key
    // sha1 hash of shared DH key
    
    BOOL result = YES;

    NSMutableDictionary *hopParams = [nodes objectAtIndex:nodes.count - 1];
    OPDiffieHellman *dh = [hopParams objectForKey:kOPCircuitHandshakeKey];

    NSData *dhSharedKey = [dh deriveSimmetricKeyDataWithResonse:[NSData dataWithBytes:data.bytes length:dhPublicKeyLen]];
    NSMutableData *baseMaterial = [NSMutableData dataWithData:dhSharedKey];
    [baseMaterial setLength:baseMaterial.length + 1];
    
    NSMutableData *keys = [NSMutableData dataWithCapacity:sha1DigestLen * 2];
    
    for (uint8 i = 0; result && i < 5; i++) {
        ((uint8 *)baseMaterial.mutableBytes)[baseMaterial.length] = i;
        switch (i) {
            case 0: { // check if key has been learned correctly
                NSData *sha1Local = [OPSHA1 digestOfData:baseMaterial];
                NSData *sha1Remote = [NSData dataWithBytes:data.bytes + dhPublicKeyLen length:sha1DigestLen];
                if (![sha1Local isEqualToData:sha1Remote]) {
                    result = NO;
                }
            } break;
            
            case 1: { // forward digest Df;
                OPSHA1 *df = [[OPSHA1 alloc] init];
                [df updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                [hopParams setObject:df forKey:kOPCircuitForwardDigestKey];
                [df release];
            } break;
                
            case 2: { // backward digest Db;
                OPSHA1 *db = [[OPSHA1 alloc] init];
                [db updateWithData:[OPSHA1 digestOfData:baseMaterial]];
                [hopParams setObject:db forKey:kOPCircuitBackwardDigestKey];
                [db release];
            } break;
                
            case 3: { // forward and backward keys material
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
            } break;
                
            case 4: { // forward and backward keys material
                [keys appendData:[OPSHA1 digestOfData:baseMaterial]];
                
                OPSimmetricKey *kf = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes length:16]];
                [hopParams setObject:kf forKey:kOPCircuitForwardSimmetricKeyKey];
                [kf release];
                OPSimmetricKey *kb = [[OPSimmetricKey alloc] initWithData:[NSData dataWithBytes:keys.bytes length:16]];
                [hopParams setObject:kb forKey:kOPCircuitBackwardSimmetricKeyKey];
                [kb release];
            }
        }
    }
    
    return result;
}

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data {
    switch (command) {
        case OPConnectionCommandCreated: {
            [self logMsg:@"OPConnectionCommandCreated"];

            if (![self finishHandshakeWithResponseData:data]) {
                [self logMsg:@"Handshake failed. Terminating connection"];
                [connection disconnect];
                return;
            }
            [self logMsg:@"Handshake successful"];
        } break;

        case OPConnectionCommandDestroy: {
            uint8_t reason = ((uint8_t *)data.bytes)[0];
            [self logMsg:@"Desroy reason: %i", reason];
        } break;
            
        default: {
            [self logMsg:@"OPConnectionCommand %i", command];
        } break;
    }
}

- (void) connection:(OPConnection *)sender onEvent:(OPConnectionEvent)event {
    switch (event) {
        case OPConnectionEventConnected: {
            [self logMsg:@"Ready to send CREATE Cell"];
            [sender sendCommand:OPConnectionCommandCreate withData:[self beginHandshakeData]];
        } break;
        
        case OPConnectionEventConnectionFailed: {
            [self logMsg:@"OPConnectionEventConnectionFailed"];
        } break;
            
        case OPConnectionEventDisconnected: {
            [self logMsg:@"OPConnectionEventDisconnected"];
        } break;            
    }
}

- (void) addNode:(OPTorNode *)node {
    NSMutableDictionary *nodeInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     node, kOPCircuitNodeKey,
                                     nil];
    [nodes addObject:nodeInfo];
}

- (void) establishWithDestinationPort:(NSUInteger)port {
    connection.delegate = self;
    OPTorNode *entryNode = [OPConsensus consensus].randomRouterNode;
    if (entryNode) {
        [self addNode:entryNode];
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

- (id) initWithDestinationPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        connection = [[OPConnection alloc] init];
        nodes = [[NSMutableArray alloc] initWithCapacity:[OPConfig config].circuitLength];
        [self establishWithDestinationPort:port];
    }
    return self;
}

- (void) dealloc {
    [connection disconnect];
    [connection release];
    [nodes release];
    
    [super dealloc];
}

@end
