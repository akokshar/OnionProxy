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
    OPConnectionHandshkeUndefined,
    OPConnectionHandshkeV1,
    OPConnectionHandshkeV2,
    OPConnectionHandshkeV3,
    OPConnectionHandshkeCertificatesUpFront,
    OPConnectionHandshkeRenegotiation,
    OPConnectionHandshkeInProtocol
} OPConnectionHandshakeType;

typedef enum {
    OPConnectionEventConnected,
    OPConnectionEventConnectionFailed,
    OPConnectionEventDataReceived,
    OPConnectionEventDisconnected
} OPConnectionEvent;

@protocol OPConnectionDelegate <NSObject>
- (void) connection:(OPConnection *)sender event:(OPConnectionEvent)event object:(id)object;
@end

@interface OPConnection : OPObject <NSStreamDelegate> {
}

@property (readonly) OPConnectionHandshakeType handshakeType;
@property (readonly) BOOL isConnected;
@property (retain) id <OPConnectionDelegate> delegate;

- (id) init;

- (BOOL) connectToIp:(NSString *)ip port:(NSUInteger)port;
- (void) disconnect;

- (void) sendData:(NSData *)data;

@end
