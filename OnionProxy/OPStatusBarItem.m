//
//  OPStatusBarItemView.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 06/06/14.
//
//

#import "OPStatusBarItem.h"
#import <Cocoa/Cocoa.h>

@protocol OPStatusBarItemViewDelegate <NSObject>
@property (strong, nonatomic) NSStatusItem *statusItem;
- (void) statusBarItemNewState:(BOOL)state;
@end

@interface OPStatusBarItemView : NSView
@property (nonatomic, setter = setIsHighlighted:) BOOL isHighlighted;
@property (assign) id<OPStatusBarItemViewDelegate>delegate;
@end

@implementation OPStatusBarItemView

@synthesize delegate = _delegate;
@synthesize isHighlighted = _isHighlighted;

- (id) initWithDelegate:(id<OPStatusBarItemViewDelegate>)aDelegate {
    NSRect statusItemRect = NSMakeRect(0.0, 0.0, [[NSStatusBar systemStatusBar] thickness], [[NSStatusBar systemStatusBar] thickness]);
    self = [super initWithFrame:statusItemRect];
    if (self) {
        _delegate = aDelegate;
        _isHighlighted = NO;
    }
    return self;
}

- (void) setIsHighlighted:(BOOL)highlighted {
    BOOL isStateChanged = (highlighted != _isHighlighted);
    _isHighlighted = highlighted;
    if (isStateChanged) {
        [self.delegate statusBarItemNewState:_isHighlighted];
        [self setNeedsDisplay:isStateChanged];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [self.delegate.statusItem drawStatusBarBackgroundInRect:dirtyRect withHighlight:self.isHighlighted];
    NSImage *icon = [NSApp applicationIconImage];
    [icon drawInRect:[self bounds]];
}

- (void)mouseDown:(NSEvent *)theEvent{
    self.isHighlighted = !self.isHighlighted;
}

- (void) dealloc {
    [super dealloc];
}

@end

@interface OPStatusBarItem() <OPStatusBarItemViewDelegate>

@end

@implementation OPStatusBarItem

@synthesize statusItem = _statusItem;
@synthesize view = _view;

- (NSView *) getView {
    return self.statusItem.view;
}

- (id) init {
    self = [super init];
    if (self) {
        self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        self.statusItem.view = [[[OPStatusBarItemView alloc] initWithDelegate:self] autorelease];
    }
    return self;
}

- (void) statusBarItemNewState:(BOOL)state {
    if (state) {
        [self.delegate statusBarItemActivated];
    }
    else {
        [self.delegate statusBarItemDeactivated];
    }
}

- (void) activate {
    ((OPStatusBarItemView *)self.statusItem.view).isHighlighted = YES;
}

- (void) deactivate {
    ((OPStatusBarItemView *)self.statusItem.view).isHighlighted = NO;
}

- (void)dealloc {
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    
    [super dealloc];
}

@end
