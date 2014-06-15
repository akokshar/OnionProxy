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
    OPCircuitEventDisconnected,
    OPCircuitEventExtended,
    OPCircuitEventTruncated,
    OPCircuitEventTimeout
} OPCircuitEvent;

@class OPCircuit;

@protocol OPCircuitDelegate
- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event;
- (void) circuit:(OPCircuit *)circuit receivedData:(NSData *)data forStream:(NSUInteger)streamId;
@end

@interface OPCircuit : OPObject <OPConnectionDelegate> {
    
}

@property (readonly, getter=getLength) NSUInteger length;

- (void) extentTo:(OPTorNode *)node;
- (void) close;

@end
