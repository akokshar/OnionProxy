//
//  OPTorNetwork.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"

@interface OPTorNetwork : OPObject


- (void) createCircuit;
- (void) extendCircuit;
- (void) closeCircuit;

@end
