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
#import "OPStream.h"

@interface OPTorNetwork() {

}

@property (retain) OPCircuit *c;
@property (retain) OPStream *s;

@end

@implementation OPTorNetwork

@synthesize c;
@synthesize s;

- (void) circuit:(OPCircuit *)circuit event:(OPCircuitEvent)event {
    switch (event) {
        case OPCircuitEventExtended: {
            [self logMsg:@"Circuit ready!. (LEN=%lu)", (unsigned long)circuit.circuitLength];
            if (self.c.isDirectoryServiceAvailable) {
                [self logMsg:@"Directory service available"];
            }
            else if (self.c.circuitLength <= 3) {
                [[OPTorDirectory directory] getRandomCacheAsync:^(OPTorNode *node) {
                    [self.c appendNode:node];
                }];
            }
        } break;

        case OPCircuitEventTruncated: {

        } break;

        case OPCircuitEventClosed: {

        } break;
    }
}

- (OPCircuit *) circuitForDirectoryService {
    if (self.c.isDirectoryServiceAvailable) {
        return self.c;
    }
    return NULL;
}

- (OPStream *) createHTTPStreamForDirectoryServiceWithRequest:(NSURLRequest *)request {
    
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
//    NSURL *testUrl = [NSURL URLWithString:@"opdir:///tor/server/d/71D7CE3A58DB476C5790244507ADC991783AB904.z"];
//    NSURLRequest *testRequest = [NSURLRequest requestWithURL:testUrl];
//
//    self.s = [OPStream directoryStreamForClient:NULL];
//    [self logMsg:@"stream created. retain count %lu", (unsigned long)self.s .retainCount];
//    [self.s open];
//    [self logMsg:@"stream opened. retain count %lu", (unsigned long)self.s .retainCount];
}

- (void) closeStream {
//    [self.s  close];
//    [self logMsg:@"stream closed. retain count %lu", (unsigned long)self.s .retainCount];
//    self.s  = NULL;
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
