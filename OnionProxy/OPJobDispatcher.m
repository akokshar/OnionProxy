//
//  OPThreadDispatcher.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/03/14.
//
//

#import "OPJobDispatcher.h"
#import "OPConfig.h"

NSString * const jobTargetKey = @"Target";
NSString * const jobSelectorKey = @"Selector";
NSString * const jobObjectKey = @"Object";
NSString * const jobIsBarierKey = @"IsBarier";

@interface OPJobDispatcher() {
    dispatch_group_t dispatchGroup;
    dispatch_queue_t dispatchQueue;
    NSMutableArray *jobs;
}

@property (atomic) NSUInteger jobsCountLimit;
@property (atomic) NSUInteger jobsCount;
@property (atomic) BOOL isPaused;

- (void) jobThread:(NSDictionary *)jobParams;
- (void) dispatch;

@end

@implementation OPJobDispatcher

- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object {
    NSDictionary *jobParamsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       (target == NULL)?[NSNull null]:target, jobTargetKey,
                                       NSStringFromSelector(selector), jobSelectorKey,
                                       (object == NULL)?[NSNull null]:object, jobObjectKey,
                                       [NSNumber numberWithBool:NO], jobIsBarierKey, nil];

    @synchronized(self) {
        [jobs addObject:jobParamsDict];
    }
    
    [self dispatch];
}

- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object delayedFor:(NSTimeInterval)seconds {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatchQueue, ^{
        [self addJobForTarget:target selector:selector object:object];
    });
    
    [self dispatch];
}

- (void) addBarierTarget:(id)target selector:(SEL)selector object:(id)object {
    NSDictionary *jobParamsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   (target == NULL)?[NSNull null]:target, jobTargetKey,
                                   NSStringFromSelector(selector), jobSelectorKey,
                                   (object == NULL)?[NSNull null]:object, jobObjectKey,
                                   [NSNumber numberWithBool:YES], jobIsBarierKey, nil];
    
    @synchronized(self) {
        [jobs addObject:jobParamsDict];
    }
    
    [self dispatch];
}

- (void) jobThread:(NSDictionary *)jobParamsDict {
    id target = [jobParamsDict objectForKey:jobTargetKey];
    SEL method = NSSelectorFromString([jobParamsDict objectForKey:jobSelectorKey]);
    id object = [jobParamsDict objectForKey:jobObjectKey];
    
    [target performSelector:method withObject:([object isKindOfClass:[NSNull class]])?NULL:object];
    
    [jobParamsDict release];
    
    self.jobsCount--;
    [self dispatch];
}

- (void) dispatch {
    if (self.isPaused) {
        return;
    }
    
    if (self.jobsCount < self.jobsCountLimit) {
        NSDictionary *jobParamsDict = NULL;
        
        @synchronized(self) {
            if ([jobs count] > 0) {
                jobParamsDict = [jobs objectAtIndex:0];
                [jobParamsDict retain];
                [jobs removeObjectAtIndex:0];
            }
        }

        if (jobParamsDict) {
            if ([(NSNumber *)[jobParamsDict objectForKey:jobIsBarierKey] boolValue]) {
                dispatch_barrier_async(dispatchQueue, ^{
                    self.jobsCount++;
                    [self jobThread:jobParamsDict];
                    //[jobParams release];
                });
            }
            else {
                dispatch_async(dispatchQueue, ^{
                    self.jobsCount++;
                    [self jobThread:jobParamsDict];
                    //[jobParams release];
                });
            }
        }
    }
}

- (void) wait {
    dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
}

- (void) pause {
    self.isPaused = YES;
}
- (void) resume {
    self.isPaused = NO;
    [self dispatch];
}

- (id) initWithMaxJobsCount:(NSUInteger)maxJobsCount {
    self = [super init];
    if (self) {
        [self logMsg:@"INIT JOBDISPATCHER"];
        
        dispatchGroup = dispatch_group_create();
        dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        
        jobs = [[NSMutableArray alloc] initWithCapacity:32];
        
        self.jobsCountLimit = maxJobsCount;
        self.jobsCount = 0;
        self.isPaused = NO;
    }
    return self;
}

- (void) dealloc {
    [jobs release];
    
    dispatch_release(dispatchQueue);
    dispatch_release(dispatchGroup);
    
    [super dealloc];
}

+ (OPJobDispatcher *) nodesBundle1 {
    static OPJobDispatcher *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPJobDispatcher alloc] initWithMaxJobsCount:[OPConfig config].nodesThreadsCount];
    });
    return instance;
}

@end
