//
//  OPAppDelegate.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPAppDelegate.h"
#import "OPStatusBarItem.h"
#import "OPTorDirectory.h"
#import "OPTorDirectoryProtocol.h"
#import "OPCircuit.h"
#import "OPTorNetwork.h"

@interface OPAppDelegate() <OPStatusBarItemDelegate> {
    OPStatusBarItem *statusBarItem;
    OPTorNetwork *torNetwork;
}

@end

@implementation OPAppDelegate

@synthesize popoverViewController = _popoverViewController;
@synthesize popover = _popover;

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSURLProtocol registerClass:[OPTorDirectoryProtocol class]];

    torNetwork = [[OPTorNetwork alloc] init];

    statusBarItem = [[OPStatusBarItem alloc] init];
    statusBarItem.delegate = self;
    [[self.tvTabView tabViewItemAtIndex:1] setView:[OPTorDirectory directory].view];
}

- (void) applicationWillTerminate:(NSNotification *)notification {
    [statusBarItem release];
    [torNetwork release];
}

- (void) applicationDidResignActive:(NSNotification *)notification {
    [statusBarItem deactivate];
}

- (void) statusBarItemActivated {
    [self.popover showRelativeToRect:statusBarItem.view.bounds ofView:statusBarItem.view preferredEdge:NSMinYEdge];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void) statusBarItemDeactivated {
    [self.popover close];
}

- (IBAction)createCircuit:(id)sender {
    [torNetwork createCircuit];
}

- (IBAction)extendCircuit:(id)sender {
    [torNetwork extendCircuit];
}

- (IBAction)closeCircuit:(id)sender {
    [torNetwork closeCircuit];
}

@end
