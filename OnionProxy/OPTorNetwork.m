//
//  OPTorNetwork.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPTorNetwork.h"
#import "OPConfig.h"
#import "OPAuthority.h"
#import "OPConsensus.h"

@interface OPTorNetwork() {
    
}

- (void) exploreNetwork;
@end

@implementation OPTorNetwork

+ (OPTorNetwork *) torNetwork {
    static OPTorNetwork *instance  = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPTorNetwork alloc] init];
    });
    return instance;
}

- (id) init {
    self = [super init];
    if (self) {
        [self exploreNetwork];
    }
    return self;
}

- (void) dealloc {
    [super dealloc];
}

-(void) exploreNetwork {
//    [self logMsg:@"I have %lu authority servers.", [OPAuthority authority].count];
//    if ([OPConsensus consensus]) {
//
//    }
}

@end
