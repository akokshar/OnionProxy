//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/03/14.
//
//

#import "OPObject.h"
#import "OPConnection.h"

@interface OPCircuit : OPObject <OPConnectionDelegate> {
    
}

@property (readonly, getter = getCircuitID) uint16_t circuitID;

- (id) initWithDestinationPort:(NSUInteger)port;
- (void) close;

@end
