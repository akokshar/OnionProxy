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
    NSStatusItem *statusItem;
}

@end

@implementation OPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSURLProtocol registerClass:[OPTorDirectoryProtocol class]];

    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
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
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
}

- (IBAction)showMainWindow:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
}

- (IBAction)createCircuit:(id)sender {
    [[OPTorNetwork network] createCircuit];
}

- (IBAction)closeCircuit:(id)sender {
    [[OPTorNetwork network] closeCircuit];
}

- (IBAction)openStream:(id)sender {
    [[OPTorNetwork network] openStream];
}

- (IBAction)closeStream:(id)sender {
    [[OPTorNetwork network] closeStream];
}

@end
