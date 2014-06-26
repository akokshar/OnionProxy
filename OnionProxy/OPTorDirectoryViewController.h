//
//  OPTorNetworkViewController.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 21/05/14.
//
//

#import <Cocoa/Cocoa.h>

@interface OPTorDirectoryViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate> {
    
}

- (void) setTotalNodesCount:(NSInteger) count;
- (void) setDirNodesCount:(NSInteger) count;
- (void) setTorFastNodesCount:(NSInteger) count;

- (void) setPreloadedDescriptorsCount:(NSInteger) count;

- (void) setConsensusValidAfter:(NSDate *) date;
- (void) setConsensusFreshUntil:(NSDate *) date;
- (void) setConsensusValidUntil:(NSDate *) date;

@property (assign) IBOutlet NSTableView *tableView;

@end
