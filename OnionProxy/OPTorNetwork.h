//
//  OPTorNetwork.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"
#import "OPCircuit.h"

@interface OPTorNetwork : OPObject <OPCircuitDelegate> {

}

- (void) createCircuit;
- (void) extendCircuit;
- (void) closeCircuit;

- (void) openStream;
- (void) closeStream;


@end
