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
#import "OPHTTPStream.h"

@interface OPTorNetwork() {

}

@property (retain) OPCircuit *c;
@property (retain) OPHTTPStream *s;

@end

@implementation OPTorNetwork

@synthesize c;
@synthesize s;

- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event {
    switch (event) {
        case OPCircuitEventExtended: {
            [self logMsg:@"Circuit ready!. (LEN=%lu)", (unsigned long)circuit.circuitLength];
        } break;

        case OPCircuitEventTruncated: {

        } break;

        case OPCircuitEventClosed: {

        } break;
    }
}

- (OPHTTPStream *) createHTTPStreamForDirectoryService {
    return NULL;
}

- (void) createCircuit {
    self.c = [[[OPCircuit alloc] initWithDelegate:self] autorelease];
    self.c.circuitLength = 3;
}

- (void) closeCircuit {
    [self logMsg:@"circuit retain count %lu", (unsigned long)self.c.retainCount];
    [self.c close];
    self.c = NULL;
}

- (void) openStream {
    self.s = [[OPHTTPStream alloc] initForDirectoryServiceWithCircuit:c client:NULL];
    [self logMsg:@"stream created. retain count %lu", (unsigned long)self.s .retainCount];
    [self.s open];
    [self logMsg:@"stream opened. retain count %lu", (unsigned long)self.s .retainCount];
}

- (void) closeStream {
    [self.s  close];
    [self logMsg:@"stream closed. retain count %lu", (unsigned long)self.s .retainCount];
    self.s  = NULL;
}

+ (OPTorNetwork *) network {
    static OPTorNetwork *instance = NULL;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPTorNetwork alloc] init];
    });

    return instance;
}

@end
