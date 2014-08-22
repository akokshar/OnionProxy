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
} OPCircuitStreamEvent;

@protocol OPCircuitStreamDelegate
- (void) streamDidReceiveData:(NSData *)data;
- (void) streamOpened;
- (void) streamClosed;
- (void) streamError;
@end

@class OPCircuit;

typedef enum {
    OPCircuitEventExtended,
    OPCircuitEventExtentionNotPossible,
    OPCircuitEventTruncated,
    OPCircuitEventClosed,
} OPCircuitEvent;

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate>

@property (assign) id<OPCircuitDelegate> delegate;

/// Number of TORs the circuit go through. Circuit is extended or truncated when this property modified.
@property (getter=getCircuitLength, setter=setCircuitLength:) NSUInteger circuitLength;

@property (readonly, getter=getIsDirectoryServiceAvailable) BOOL isDirectoryServiceAvailable;

- (id) initWithDelegate:(id<OPCircuitDelegate>)delegate;

- (void) appendNode:(OPTorNode *)node;

/**
 * Destroy circuit and close corresponding TCP connection.
 */
- (void) close;

/**
 * Create new stream context to access directory service for specified client.
 * Return 0 if directory service is not afailable on this Circuit
 */
- (OPStreamId) openDirectoryStreamWithDelegate:(id<OPCircuitStreamDelegate>)delegate;

/**
 * Free resources allocated by <code> - (OPStream *) buildStreamForClient:(id<OPStreamClientDelegate>)client;</code>
 */
- (void) closeStream:(OPStreamId)stream;

- (void) sendData:(NSData *)data overStream:(OPStreamId)streamId;

@end
