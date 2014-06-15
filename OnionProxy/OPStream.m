//
//  OPStream.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPStream.h"

@interface OPStream() {

}

@property (nonatomic, retain) OPCircuit *circuit;

@end

@implementation OPStream

- (id) initWithCircuit:(OPCircuit *)circuit {
    self = [super init];
    if (self) {
        self.circuit = circuit;
    }
    return self;
}

- (void) dealloc {
    self.circuit = NULL;

    [super dealloc];
}

@end
