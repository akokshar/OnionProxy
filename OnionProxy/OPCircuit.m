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
        [connection connectToIp:entryNode.ip port:entryNode.orPort];
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
