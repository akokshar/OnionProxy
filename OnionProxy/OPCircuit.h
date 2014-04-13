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

- (id) initWithDestinationPort:(NSUInteger)port;
- (void) close;

@end
