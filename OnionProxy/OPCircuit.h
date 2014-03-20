//
//  OPCircuit.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 06/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"
#import "OPTorNode.h"

@interface OPCircuit : OPObject

- (id) initWithLayersCount:(NSUInteger)layersCount andDestinationPort:(uint16_t)port;

@end
