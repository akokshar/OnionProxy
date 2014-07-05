//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/03/14.
//
//

#import "OPObject.h"
#import "OPConnection.h"

typedef uint16 OPStreamId;

typedef enum {
    OPStreamEventConnected,
    OPStreamEventDataReceived,
    OPStreamEventDisconnected
} OPStreamEvent;

@protocol OPStreamDelegate
- (void) stream:(OPStreamId)streamId receivedData:(NSData *)data;
- (void) stream:(OPStreamId)streamId event:(OPStreamEvent)event;
@end

@class OPCircuit;

typedef enum {
    OPCircuitEventExtended,
    OPCircuitEventTruncated,
    OPCircuitEventClosed,
} OPCircuitEvent;

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate>

@property (assign) id<OPCircuitDelegate> delegate;

/// Number of TORs the circuit go through. Circuit is extended or truncated when this property modified.
@property (getter=getLength, setter=setLength:) NSUInteger length;

- (id) initWithDelegate:(id<OPCircuitDelegate>)delegate;

- (void) appendNode:(OPTorNode *)node;

/**
 * Destroy circuit and close corresponding TCP connection.
 */
- (void) close;

/**
 * Create new stream context for specified client.
 */
- (OPStreamId) openStreamForClient:(id<OPStreamDelegate>)client;

/**
 * Free resources allocated by <code> - (OPStream *) buildStreamForClient:(id<OPStreamClientDelegate>)client;</code>
 */
- (void) closeStream:(OPStreamId)stream;

@end
