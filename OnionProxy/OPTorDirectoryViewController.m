//
//  OPTorNetworkViewController.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 21/05/14.
//
//

#import "OPTorDirectoryViewController.h"

typedef enum {
    rowTotalNodesCount,
    rowDirNodesCount,
    rowTorFastNodesCount,
    rowSpace1,
    rowConsensusValidAfter,
    rowConsensusValidBefore,
    rowConsensusFreshUntil
} rowIndexes;

@interface OPTorDirectoryViewController () {
    NSDictionary *names;
    NSMutableDictionary *values;
}

@end

@implementation OPTorDirectoryViewController

- (void) updateValueAtRow:(NSInteger)row {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:1]];
    });
}

- (void) setTotalNodesCount:(NSInteger) count {
    [values setObject:[NSString stringWithFormat:@"%li", (long)count] forKey:[NSNumber numberWithInt:rowTotalNodesCount]];
    [self updateValueAtRow:rowTotalNodesCount];
}

- (void) setDirNodesCount:(NSInteger) count {
    [values setObject:[NSString stringWithFormat:@"%li", (long)count] forKey:[NSNumber numberWithInt:rowDirNodesCount]];
    [self updateValueAtRow:rowDirNodesCount];
}

- (void) setTorFastNodesCount:(NSInteger) count {
    [values setObject:[NSString stringWithFormat:@"%li", (long)count] forKey:[NSNumber numberWithInt:rowTorFastNodesCount]];
    [self updateValueAtRow:rowTorFastNodesCount];
}

- (void) setConsensusValidAfter:(NSDate *) date {
    NSString *dateStr = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    [values setObject:dateStr forKey:[NSNumber numberWithInt:rowConsensusValidAfter]];
    [self updateValueAtRow:rowConsensusValidAfter];
}

- (void) setConsensusFreshUntil:(NSDate *) date {
    NSString *dateStr = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    [values setObject:dateStr forKey:[NSNumber numberWithInt:rowConsensusValidBefore]];
    [self updateValueAtRow:rowConsensusValidBefore];
}

- (void) setConsensusValidUntil:(NSDate *) date {
    NSString *dateStr = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    [values setObject:dateStr forKey:[NSNumber numberWithInt:rowConsensusFreshUntil]];
    [self updateValueAtRow:rowConsensusFreshUntil];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView {
    return names.count;
}

-(NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"Cell" owner:self];
    
    if (cell == NULL) {
        cell = [[[NSTextField alloc] init] autorelease];
        cell.identifier = @"Cell";
        [cell setEditable:NO];
        [cell setBordered:NO];
        [cell setDrawsBackground:NO];
    }
    
    if ([tableColumn.identifier isEqualToString:@"Name"]) {
        cell.stringValue = [names objectForKey:[NSNumber numberWithInteger:row]];
    }
    else {
        cell.stringValue = [values objectForKey:[NSNumber numberWithInteger:row]];
    }
    
    return cell;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        names = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @"Total", [NSNumber numberWithInt:rowTotalNodesCount],
                 @"Directory servers", [NSNumber numberWithInt:rowDirNodesCount],
                 @"Fast routers", [NSNumber numberWithInt:rowTorFastNodesCount],
                 @"", [NSNumber numberWithInt:rowSpace1],
                 @"Consensus valid after", [NSNumber numberWithInt:rowConsensusValidAfter],
                 @"Consensus valid before", [NSNumber numberWithInt:rowConsensusValidBefore],
                 @"Consensus fresh until", [NSNumber numberWithInt:rowConsensusFreshUntil],
                 nil];
        values = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                  @"0", [NSNumber numberWithInt:rowTotalNodesCount],
                  @"0", [NSNumber numberWithInt:rowDirNodesCount],
                  @"0", [NSNumber numberWithInt:rowTorFastNodesCount],
                  @"", [NSNumber numberWithInt:rowSpace1],
                  @"", [NSNumber numberWithInt:rowConsensusValidAfter],
                  @"", [NSNumber numberWithInt:rowConsensusValidBefore],
                  @"", [NSNumber numberWithInt:rowConsensusFreshUntil],
                  nil];
    }
    return self;
}

- (void) dealloc {
    [names release];
    [values release];
    
    [super dealloc];
}

@end
