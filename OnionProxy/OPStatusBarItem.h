//
//  OPStatusBarItemView.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 06/06/14.
//
//

#import "OPObject.h"

@protocol OPStatusBarItemDelegate <NSObject>
- (void) statusBarItemActivated;
- (void) statusBarItemDeactivated;
@end

@interface OPStatusBarItem : OPObject

@property (assign) IBOutlet id<OPStatusBarItemDelegate> delegate;

@property (readonly, getter=getView) NSView *view;

- (void) activate;
- (void) deactivate;

@end
