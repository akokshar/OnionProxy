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

NSString * const circuitNodeKey = @"NodeKey";
NSString * const circuitSessionKeyKey = @"SessionKeyKey";

@interface OPCircuit() {
    NSMutableArray *nodes;
    OPConnection *connection;
}

- (void) addNode:(OPTorNode *)node;
- (void) establishWithDestinationPort:(NSUInteger)port;

@end

@implementation OPCircuit

- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(id)data {
    switch (command) {
        case OPConnectionCommandCerts: {
            [self logMsg:@"OPConnectionCommandCerts"];
        } break;

        case OPConnectionCommandAuthChallenge: {
            [self logMsg:@"OPConnectionCommandAuthChallenge"];
        } break;

        case OPConnectionCommandNetInfo: {
            [self logMsg:@"OPConnectionCommandNetInfo"];
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
            
            OPTorNode *node = [[nodes objectAtIndex:0] objectForKey:circuitNodeKey];
            
            [self logMsg:@"Ready to send CREATE Cell"];
            
            OPDiffieHellman *dh = [[OPDiffieHellman alloc] init];
            //[self logMsg:@"E=%@", [self hexStringFromData:dh.EData]];
            
            OPSimmetricKey *simmetricKey = [[OPSimmetricKey alloc] initWithLength:16];
            //[self logMsg:@"Symmetric key=%@", [self hexStringFromData:simmetricKey.keyData]];
            
            NSMutableData *payloadPart1Clear = [NSMutableData dataWithCapacity:simmetricKey.keyData.length + 70];
            [payloadPart1Clear appendData:simmetricKey.keyData];
            [payloadPart1Clear appendBytes:dh.AData.bytes length:70];
            NSMutableData *payloadPart2Clear = [NSMutableData dataWithBytes:dh.AData.bytes + 70 length:dh.AData.length - 70];
            
            NSData *payload1 = [node.onionKey encryptData:payloadPart1Clear];
            NSData *payload2 = [simmetricKey encryptData:payloadPart2Clear];
            
            NSMutableData *packet = [NSMutableData data];
            [packet appendData:payload1];
            [packet appendData:payload2];
            
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
    OPSimmetricKey *sessionKey = [[OPSimmetricKey alloc] init];
    NSMutableDictionary *nodeInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     node, circuitNodeKey,
                                     sessionKey, circuitSessionKeyKey,
                                     nil];
    [nodes addObject:nodeInfo];

    [sessionKey release];
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
