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

NSUInteger const OPKeyLen = 16;

NSString * const circuitNodeKey = @"NodeKey";
NSString * const circuitSessionKeyKey = @"SessionKeyKey";
NSString * const circuitHandshakeKey = @"HandshakeKey";

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

- (void) beginHandshake;
- (void) finishHandshakeWithDada:(NSData *)data;

- (void) addNode:(OPTorNode *)node;
- (void) establishWithDestinationPort:(NSUInteger)port;

@end

@implementation OPCircuit

- (void) beginHandshake {
    
}

- (void) finishHandshakeWithDada:(NSData *)data {
    
}

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data {
    switch (command) {
        case OPConnectionCommandCreated: {
            [self logMsg:@"OPConnectionCommandCreated"];
            
            NSMutableDictionary *hopSettings = [nodes objectAtIndex:0];
//            OPTorNode *node = [hopSettings objectForKey:circuitNodeKey];
            OPDiffieHellman *dh = [hopSettings objectForKey:circuitHandshakeKey];
//            OPSimmetricKey *simmetricKey = [hopSettings objectForKey:circuitSessionKeyKey];
            
            NSData *baseMaterial = [dh deriveSimmetricKeyDataWithResonse:[NSData dataWithBytes:data.bytes length:128]];
            NSMutableData *k = [[NSMutableData alloc] init]; //WithCapacity:baseMaterial.length + 1];
            for (char i = 0; i < 5; i++) {
                NSMutableData *temp = [NSMutableData dataWithCapacity:baseMaterial.length + 1];
                [temp appendData:baseMaterial];
                [temp appendBytes:&i length:1];
                
                [self logMsg:@"%@", [OPSHA1 digestOfData:temp]];
                [self logMsg:@"%@\n", [NSData dataWithBytes:data.bytes + 128 length:20]];
            }
            
            [k release];
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
            
            // Connected to the first node.
            // CREATEv1 Cell payload is as this:
            //      TAP handshake
            //            PK-encrypted:
            //              Padding                       [PK_PAD_LEN bytes]
            //              Symmetric key                 [KEY_LEN bytes]
            //              First part of g^x             [PK_ENC_LEN-PK_PAD_LEN-KEY_LEN bytes]
            //              Symmetrically encrypted:
            //                  Second part of g^x            [DH_LEN-(PK_ENC_LEN-PK_PAD_LEN-KEY_LEN) bytes]
            //
            NSMutableDictionary *hopSettings = [nodes objectAtIndex:0];
            
            OPDiffieHellman *dh = [[OPDiffieHellman alloc] init];
            [hopSettings setObject:dh forKey:circuitHandshakeKey];
            
            OPSimmetricKey *simmetricKey = [[OPSimmetricKey alloc] initWithLength:16];
            [hopSettings setObject:simmetricKey forKey:circuitSessionKeyKey];

            OPTorNode *node = [hopSettings objectForKey:circuitNodeKey];
            
            NSMutableData *payloadPart1Clear = [NSMutableData dataWithCapacity:simmetricKey.keyData.length + 70];
            [payloadPart1Clear appendData:simmetricKey.keyData];
            [payloadPart1Clear appendBytes:dh.request.bytes length:70];
            
            NSMutableData *payloadPart2Clear = [NSMutableData dataWithBytes:dh.request.bytes + 70 length:dh.request.length - 70];
            
            NSMutableData *packet = [NSMutableData data];
            [packet appendData:[node.onionKey encryptData:payloadPart1Clear]];
            [packet appendData:[simmetricKey encryptData:payloadPart2Clear]];
            
            [self logMsg:@"Sending Create circuit request: %lu bytes", (unsigned long)packet.length];
            [sender sendCommand:OPConnectionCommandCreate withData:packet];
            
            [simmetricKey release];
            [dh release];
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
//    OPSimmetricKey *sessionKey = [[OPSimmetricKey alloc] init];
    NSMutableDictionary *nodeInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     node, circuitNodeKey,
//                                     sessionKey, circuitSessionKeyKey,
                                     nil];
    [nodes addObject:nodeInfo];

//    [sessionKey release];
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
