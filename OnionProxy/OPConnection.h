//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 06/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"
#import "OPTorNode.h"

@class OPConnection;

typedef enum {
    OPConnectionProtocolVersionUnknown = 0x0000,
    OPConnectionProtocolVersionV1 = 0x0001,
    OPConnectionProtocolVersionV2 = 0x0002,
    OPConnectionProtocolVersionV3 = 0x0003
} OPConnectionProtocolVersion;

typedef enum {
    OPConnectionHandshkeUnknown,
    OPConnectionHandshkeCertificatesUpFront,
    OPConnectionHandshkeRenegotiation,
    OPConnectionHandshkeInProtocol
} OPConnectionHandshakeType;

typedef enum {
    OPConnectionEventConnected,
    OPConnectionEventConnectionFailed,
    OPConnectionEventDisconnected
} OPConnectionEvent;

typedef enum {
    OPConnectionCommandPadding = 0,
    OPConnectionCommandCreate = 1,
    OPConnectionCommandCreated = 2,
    OPConnectionCommandRelay = 3,
    OPConnectionCommandDestroy = 4,
    OPConnectionCommandCreateFast = 5,
    OPConnectionCommandCreatedFast = 6,
    OPConnectionCommandVersions = 7,
    OPConnectionCommandNetInfo = 8,
    OPConnectionCommandRelayEarly = 9,
    OPConnectionCommandCreate2 = 10,
    OPConnectionCommandCreated2 = 11,
    OPConnectionCommandVPadding = 128,
    OPConnectionCommandCerts = 129,
    OPConnectionCommandAuthChallenge = 130,
    OPConnectionCommandAuthenticate = 131,
    OPConnectionCommandAuthorize = 132
} OPConnectionCommand;

@protocol OPConnectionDelegate <NSObject>
- (void) connection:(OPConnection *)sender onCommand:(OPConnectionCommand)command withData:(NSData *)data;
- (void) connection:(OPConnection *)sender onEvent:(OPConnectionEvent)event;
@end

@interface OPConnection : OPObject <NSStreamDelegate> {
}

@property (readonly, getter = getCircuitID) uint16_t circuitID;
@property (readonly) OPConnectionHandshakeType handshakeType;
@property (readonly) OPConnectionProtocolVersion protocolVersion;
@property (readonly) BOOL isConnected;

+ (OPConnection *) connectionWithDelegate:(id<OPConnectionDelegate>)delegate;
- (id) initWithDelegate:(id<OPConnectionDelegate>)delegate;

- (BOOL) connectToNode:(OPTorNode *)node;
- (void) disconnect;

- (void) sendCommand:(OPConnectionCommand)command withData:(NSData *)data;

@end
