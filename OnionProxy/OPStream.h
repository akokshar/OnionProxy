//
//  OPStream.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"

@protocol OPStreamCircuitDelegate <NSObject>

@end

@interface OPStream : OPObject

- (id) initWithCircuit:(id<OPStreamCircuitDelegate>)circuit;

@end
