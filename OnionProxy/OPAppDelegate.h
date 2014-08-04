//
//  OPAppDelegate.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 08/02/14.
//
//

#import <Cocoa/Cocoa.h>

@interface OPAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSMenu *mainMenu;
@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSTabView *tabView;

- (IBAction)showMainWindow:(id)sender;

- (IBAction)createCircuit:(id)sender;
- (IBAction)closeCircuit:(id)sender;

- (IBAction)fetch:(id)sender;;

- (IBAction)openStream:(id)sender;
- (IBAction)closeStream:(id)sender;

@end
