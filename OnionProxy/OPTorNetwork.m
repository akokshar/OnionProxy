//
//  OPTorNetwork.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPTorNetwork.h"
#import "OPTorDirectory.h"
#import "OPCircuit.h"

@interface OPTorNetwork() {

}

@property (retain) OPCircuit *c;
@property (assign) OPStreamId s;

@end

@implementation OPTorNetwork

@synthesize c;
@synthesize s;

- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event {
    switch (event) {
        case OPCircuitEventExtended: {
            [self logMsg:@"Circuit ready!. (LEN=%lu)", (unsigned long)circuit.length];
        } break;

        case OPCircuitEventTruncated: {

        } break;

        case OPCircuitEventClosed: {

        } break;
    }
}

- (void) createCircuit {
    self.c = [[[OPCircuit alloc] initWithDelegate:self] autorelease];
    self.c.length = 3;
}

- (void) closeCircuit {
    [self logMsg:@"circuit retain count %lu", (unsigned long)self.c.retainCount];
    self.c = NULL;
}

- (void) openStream {
    self.c.length++;
//    self.s = [self.c openStreamForClient:NULL];
}

- (void) closeStream {
    [self.c closeStream:self.s];
}

@end
