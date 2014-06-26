//
//  OPAppDelegate.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPAppDelegate.h"
#import "OPTorDirectory.h"
#import "OPTorDirectoryProtocol.h"
#import "OPCircuit.h"
#import "OPTorNetwork.h"

@interface OPAppDelegate() {
    OPTorNetwork *torNetwork;
}

@end

@implementation OPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSURLProtocol registerClass:[OPTorDirectoryProtocol class]];

    torNetwork = [[OPTorNetwork alloc] init];

    NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem retain];
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"icon" ofType:@"icns"]];
    NSSize s = {[NSStatusBar systemStatusBar].thickness - 4, [NSStatusBar systemStatusBar].thickness - 4};
    [icon setSize:s];
    statusItem.image = icon;
    [icon release];
    statusItem.menu = self.mainMenu;
    statusItem.highlightMode = YES;
    [[self.tabView tabViewItemAtIndex:1] setView:[OPTorDirectory directory].view];

}

- (void) applicationWillTerminate:(NSNotification *)notification {
    [torNetwork release];
}

- (IBAction)showMainWindow:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
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

- (IBAction)openStream:(id)sender {
    [torNetwork openStream];
}

- (IBAction)closeStream:(id)sender {
    [torNetwork closeStream];
}

@end
