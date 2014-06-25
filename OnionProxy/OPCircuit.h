//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/03/14.
//
//

#import "OPObject.h"
#import "OPConnection.h"

typedef enum {
    OPCircuitEventConnected,
    OPCircuitEventConnectionFailed,
    OPCircuitEventDisconnected,
    OPCircuitEventClosed,
    OPCircuitEventExtended,
    OPCircuitEventExtentionFailed,
    OPCircuitEventTruncated
} OPCircuitEvent;

typedef uint16 StreamId;

@class OPCircuit;

@protocol OPStreamDelegate

@end

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate> {
    
}

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
 * Prepare new stream context for specified client.
 */
- (StreamId) addStreamForClient:(id<OPStreamDelegate>)client;

/**
 * Free resources allocated by <code> -(StreamId) addStreamForClient:(id<OPStreamDelegate>)client;</code>
 */
- (void) removeStreamWithStreamId:(StreamId)streamId;

/**
 * Open stream to a specified Host
 */
- (void) connectStreamWithStreamId:(StreamId)streamId toHostWithName:(NSString *)host port:(NSUInteger)port;

@end
