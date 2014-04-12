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

uint16_t const OPCircuitProtocolVersionV1 = 0x0001;
uint16_t const OPCircuitProtocolVersionV2 = 0x0002;
uint16_t const OPCircuitProtocolVersionV3 = 0x0003;

// Fixed-length cell
uint8_t const commandCellPadding = 0;   //(Padding)                 (See Sec 7.2)
uint8_t const commandCellCreate = 1;    //(Create a circuit)        (See Sec 5.1)
uint8_t const commandCellCreated = 2;   //(Acknowledge create)      (See Sec 5.1)
//3 -- RELAY       //(End-to-end data)         (See Sec 5.5 and 6)
uint8_t const commandCellDestroy = 4;   //(Stop using a circuit)    (See Sec 5.4)
//5 -- CREATE_FAST //(Create a circuit, no PK) (See Sec 5.1)
//6 -- CREATED_FAST// (Circuit created, no PK) (See Sec 5.1)
uint8_t const commandCellNetinfo = 8;   //(Time and address info)   (See Sec 4.5)
//9 -- RELAY_EARLY //(End-to-end data; limited)(See Sec 5.6)
uint8_t const commandCellCreate2 = 10;  //(Extended CREATE cell)    (See Sec 5.1)
uint8_t const commandCellCreated2 = 11; //(Extended CREATED cell)   (See Sec 5.1)

// Variable-length command values
uint8_t const commandCellVersions = 7;  //(Negotiate proto version) (See Sec 4)
//128 -- VPADDING  //(Variable-length padding) (See Sec 7.2)
uint8_t const commandCellCerts = 129;    //(Certificates)            (See Sec 4.2)
uint8_t const commandCellAuthChallenge = 130;   //(Challenge value)    (See Sec 4.3)
uint8_t const commandCellAuthenticate = 131;    //(Client authentication)(See Sec 4.5)
//132 -- AUTHORIZE //(Client authorization)    (Not yet used)

#pragma pack(1)
typedef struct {
    uint16_t CircID;    // [CIRCID_LEN bytes]
    uint8_t Command;    // [1 byte]
    uint8_t Payload[];  // [PAYLOAD_LEN bytes] (padded with 0 bytes)
} CELLv1;
#pragma pack()

#pragma pack(1)
typedef struct {
    uint16_t CircID;    // [CIRCID_LEN octets]
    uint8_t Command;    // [1 octet]
    uint16_t Length;    // [2 octets; big-endian integer]
    uint8_t Payload[];  // [Length bytes]
} CELLv2;
#pragma pack()

@interface OPCircuit() {
    NSMutableArray *nodes;
    OPConnection *connection;
}

+ (uint16_t) generateCircuitID;

- (void) addNode:(OPTorNode *)node;
- (void) establishWithDestinationPort:(NSUInteger)port;

@end

@implementation OPCircuit

@synthesize circuitID = _circuitID;

- (uint16_t) getCircuitID {
    if (_circuitID == 0) {
        _circuitID = [OPCircuit generateCircuitID];
    }
    return _circuitID;
}

+ (uint16_t) generateCircuitID {
    static uint16_t lastID = 0;
    return lastID + arc4random() % 13;
}

- (void) connection:(OPConnection *)sender event:(OPConnectionEvent)event object:(id)object {
    switch (event) {
        case OPConnectionEventConnected: {
            
            if (connection.handshakeType == 1) {
                //
            }
            else {
                size_t cellSize = sizeof(CELLv2) + 4;
                CELLv2 *versionsCell = malloc(cellSize);
                versionsCell->CircID = self.circuitID;
                versionsCell->Command = commandCellVersions;
                versionsCell->Length = CFSwapInt16HostToBig(4);
                versionsCell->Payload[0] = 0;
                versionsCell->Payload[1] = 3;
                versionsCell->Payload[2] = 0;
                versionsCell->Payload[3] = 2;
                //[self logMsg:@"sizeof %lu", cellSize];
                [sender sendData:[NSData dataWithBytes:versionsCell length:cellSize]];
                free(versionsCell);
            }
            
            return;
        } break;
        
        case OPConnectionEventConnectionFailed: {
            
        } break;
            
        case OPConnectionEventDataReceived: {
            [self logMsg:@"OPConnectionEventDataReceived %lu bytes", (unsigned long)[(NSData *)object length]];
            
            NSData *packetBytes = (NSData *)object;
            CELLv2 *cell = (CELLv2 *)[packetBytes bytes];

            [self logMsg:@"self circuitID='%i', received circuitID='%i'", self.circuitID, CFSwapInt16BigToHost(cell->CircID)];
            
            switch (cell->Command) {
                case commandCellVersions: {
                    uint16_t *serverVersion = (uint16_t *)cell->Payload;
                    uint16_t payloadLen = CFSwapInt16BigToHost(cell->Length);
                    for (int i = 0; i < payloadLen / sizeof(uint16_t); i++) {
                        [self logMsg:@"Server suport verion '%i'", CFSwapInt16BigToHost(serverVersion[i])];
                    }
                } break;
                
                case commandCellCerts: {
                    [self logMsg:@"commandCellCerts"];
                } break;
                    
                case commandCellAuthenticate: {
                    [self logMsg:@"commandCellAuthenticate"];
                } break;
                    
                case commandCellNetinfo: {
                    [self logMsg:@"commandCellNetinfo"];
                } break;
                    
                default: {
                    [self logMsg:@"COMMAND %i", cell->Command];
                }
            }
            
        } break;
            
        case OPConnectionEventDisconnected: {
            
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
        _circuitID = 0;
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
