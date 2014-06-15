//
//  OPAppDelegate.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import <Cocoa/Cocoa.h>

@interface OPAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSTabView *tvTabView;

@property (assign) IBOutlet NSViewController *popoverViewController;
@property (assign) IBOutlet NSPopover *popover;

- (IBAction)createCircuit:(id)sender;
- (IBAction)extendCircuit:(id)sender;
- (IBAction)closeCircuit:(id)sender;

@end
