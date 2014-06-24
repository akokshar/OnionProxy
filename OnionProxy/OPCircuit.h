//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/03/14.
//
//

#import "OPObject.h"
#import "OPConnection.h"
#import "OPStream.h"

typedef enum {
    OPCircuitEventConnected,
    OPCircuitEventConnectionFailed,
    OPCircuitEventDisconnected,
    OPCircuitEventClosed,
    OPCircuitEventExtended,
    OPCircuitEventExtentionFailed,
    OPCircuitEventTruncated
} OPCircuitEvent;

@class OPCircuit;

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate, OPStreamCircuitDelegate> {
    
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
 * Create stream object.
 */
- (OPStream *) createStream;

@end
