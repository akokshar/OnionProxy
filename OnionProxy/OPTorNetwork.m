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

@end

@implementation OPTorNetwork

@synthesize c;

- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event {
    switch (event) {
        case OPCircuitEventConnected: {

        } break;

        case OPCircuitEventConnectionFailed: {

        } break;

        case OPCircuitEventDisconnected: {

        } break;

        case OPCircuitEventClosed: {

        } break;

        case OPCircuitEventExtended: {
            if (circuit.length < 3) {
                [circuit extentTo:[[OPTorDirectory directory] getRandomRouter]];
            }
        } break;

        case OPCircuitEventExtentionFailed: {

        } break;

        case OPCircuitEventTruncated: {

        } break;
    }
}

- (void) createCircuit {
    self.c = [[[OPCircuit alloc] initWithDelegate:self] autorelease];
}

- (void) extendCircuit {
    OPTorNode *node = [[OPTorDirectory directory] getRandomRouter];
    if (node) {
        [self.c extentTo:node];
    }
    else {
        [self logMsg:@"Directory returned no router"];
    }
}

- (void) closeCircuit {
    [self logMsg:@"circuit retain count %lu", (unsigned long)self.c.retainCount];
    self.c = NULL;
}

- (void) openStream {
    [self.c openStreamForClient:NULL];
}

- (void) closeStream {

}

@end
