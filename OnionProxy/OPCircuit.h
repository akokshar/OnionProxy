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
    OPStreamEventDisconnected
} OPStreamEvent;

@protocol OPStreamDelegate
- (void) stream:(OPStreamId)streamId receivedData:(NSData *)data;
- (void) stream:(OPStreamId)streamId event:(OPStreamEvent)event;
@end

@class OPCircuit;

typedef enum {
    OPCircuitEventConnected,
    OPCircuitEventConnectionFailed,
    OPCircuitEventDisconnected,
    OPCircuitEventClosed,
    OPCircuitEventExtended,
    OPCircuitEventExtentionFailed,
    OPCircuitEventTruncated
} OPCircuitEvent;

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate>

@property (assign) id<OPCircuitDelegate> delegate;

/// Number of TORs the circuit go through
@property (readonly, getter=getLength) NSUInteger length;

- (id) initWithDelegate:(id<OPCircuitDelegate>)delegate;

/** 
 * Extend circuit acynchronously. If command accepted, completionHandler will be called when extention completed.
 * @return YES if command was accepted, NO otherwise
 */
- (BOOL) extentTo:(OPTorNode *)node;

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
