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

@property (retain) OPCircuit *circuit;

@end

@implementation OPTorNetwork

@synthesize circuit;

- (void) createCircuit {
    self.circuit = [[OPCircuit alloc] init];
}

- (void) extendCircuit {
    OPTorNode *node = [[OPTorDirectory directory] getRandomRouter];
    if (node) {
        [self.circuit extentTo:node];
    }
    else {
        [self logMsg:@"Directory returned no router"];
    }
}

- (void) closeCircuit {
    self.circuit = NULL;
}

@end
