//
//  OPAppDelegate.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPAppDelegate.h"
#import "OPCircuit.h"

@interface OPAppDelegate() {
    OPCircuit *circuit;
}

@end

@implementation OPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {

}

- (void) applicationWillTerminate:(NSNotification *)notification {

}

- (IBAction)TEST:(id)sender {
    circuit = [[OPCircuit alloc] initWithDestinationPort:80];
}

- (IBAction)TEST2:(id)sender {
    if (circuit) {
        [circuit close];
        [circuit release];
        circuit = NULL;
    }
}

@end
