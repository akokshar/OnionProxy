//
//  OPAppDelegate.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import "OPAppDelegate.h"
#import "OPTorDirectory.h"
#import "OPProtocol.h"
#import "OPCircuit.h"
#import "OPTorNetwork.h"
#import "OPListener.h"
#import "OPHTTPProxy.h"

@interface OPAppDelegate() {
    NSStatusItem *statusItem;
    OPListener *listener;
}

@end

@implementation OPAppDelegate

- (void) listener:(OPListener *)listener connectionWithInputStream:(NSInputStream *)iStream andOutputStream:(NSOutputStream *)oStream {
    [OPHTTPProxy serveConnectionWithInputStream:iStream andOutputStream:oStream];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSURLProtocol registerClass:[OPProtocol class]];

    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem retain];
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Icons" ofType:@"icns"]];
    NSSize s = {[NSStatusBar systemStatusBar].thickness - 4, [NSStatusBar systemStatusBar].thickness - 4};
    [icon setSize:s];
    statusItem.image = icon;
    [icon release];
    statusItem.menu = self.mainMenu;
    statusItem.highlightMode = YES;
    [[self.tabView tabViewItemAtIndex:1] setView:[OPTorDirectory directory].view];

    listener = [[OPListener alloc] initWithDelegate:self];
    [listener listenOnIPv4:@"127.0.0.1" andPort:8080];
}

- (void) applicationWillTerminate:(NSNotification *)notification {
    [listener release];
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

- (IBAction)fetch:(id)sender {
    [[OPTorDirectory directory] testFetchOneDescriptor];
}

- (IBAction)openStream:(id)sender {
    [[OPTorNetwork network] openStream];
}

- (IBAction)closeStream:(id)sender {
    [[OPTorNetwork network] closeStream];
}

@end
