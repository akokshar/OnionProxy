//
//  OPAppDelegate.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPAppDelegate.h"
#import "OPConsensus.h"
#import "OPAuthority.h"
#import "OPTorNetwork.h"

@interface OPAppDelegate() {
  OPTorNetwork *torNetwork;
}

@end

@implementation OPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    torNetwork = [OPTorNetwork torNetwork];
    [self.tfConsensusNodesCount setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)[OPAuthority authority].count]];
}

- (void) applicationWillTerminate:(NSNotification *)notification {
//    [torNetwork release];
}

@end
