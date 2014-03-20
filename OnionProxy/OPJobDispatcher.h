//
//  OPThreadDispatcher.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"

@interface OPJobDispatcher : OPObject {
    
}

- (id) initWithMaxJobsCount:(NSUInteger)maxJobsCount;

+ (OPJobDispatcher *) nodesBundle1;

- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object;
- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object delayedFor:(NSTimeInterval)seconds;
- (void) addBarierTarget:(id)target selector:(SEL)selector object:(id)object;
- (void) wait;

- (void) pause;
- (void) resume;

@end
