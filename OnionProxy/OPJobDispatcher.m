//
//  OPThreadDispatcher.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/03/14.
//
//

#import "OPJobDispatcher.h"
#import "OPConfig.h"

NSString * const jobInvocationOperationKey = @"Target";
NSString * const jobTargetKey = @"Target";
NSString * const jobSelectorKey = @"Selector";
NSString * const jobObjectKey = @"Object";
NSString * const jobIsBarierKey = @"IsBarier";

@interface OPJobDispatcher() {
    dispatch_queue_t dispatchQueue;
    NSMutableArray *jobs;
}

@property (atomic) NSUInteger jobsCountLimit;
@property (atomic) NSUInteger jobsCount;
@property (atomic) BOOL isPaused;

- (void) addJobWithParams:(NSDictionary *)params;
- (void) runJobWithParams:(NSDictionary *)params;
- (void) dispatch;

@end

@implementation OPJobDispatcher

- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object {
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:target selector:selector object:object];
    NSDictionary *jobParamsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   operation, jobInvocationOperationKey,
                                   [NSNumber numberWithBool:NO], jobIsBarierKey,
                                   nil];
    [operation release];
    [self addJobWithParams:jobParamsDict];
    [self dispatch];
}

- (void) addJobForTarget:(id)target selector:(SEL)selector object:(id)object delayedFor:(NSTimeInterval)seconds {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatchQueue, ^{
        //[self logMsg:@"Dispatch delayed job '%@' with object", NSStringFromSelector(selector)];
        [self addJobForTarget:target selector:selector object:object];
    });
}

- (void) addBarierTarget:(id)target selector:(SEL)selector object:(id)object {
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:target selector:selector object:object];
    NSDictionary *jobParamsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   operation, jobInvocationOperationKey,
                                   [NSNumber numberWithBool:YES], jobIsBarierKey, nil];
    [operation release];
    [self addJobWithParams:jobParamsDict];
    [self dispatch];
}

- (void) addJobWithParams:(NSDictionary *)params {
    @synchronized(self) {
        [jobs addObject:params];
    }
}

- (void) runJobWithParams:(NSDictionary *)params {
    NSInvocationOperation *operation = [params objectForKey:jobInvocationOperationKey];
    [[operation invocation] invoke];
    
    self.jobsCount--;    
    [self dispatch];
}

- (void) dispatch {
    if (self.isPaused) {
        return;
    }
    
    if (self.jobsCount >= self.jobsCountLimit) {
        return;
    }
    
    NSDictionary *jobParamsDict = NULL;
    
    @synchronized(self) {
        if ([jobs count] > 0) {
            jobParamsDict = [jobs objectAtIndex:0];
            [jobParamsDict retain];
            [jobs removeObjectAtIndex:0];
        }
    }

    if (jobParamsDict) {
        self.jobsCount++;
        if ([(NSNumber *)[jobParamsDict objectForKey:jobIsBarierKey] boolValue]) {
            dispatch_barrier_async(dispatchQueue, ^{
                [self runJobWithParams:jobParamsDict];
            });
        }
        else {
            dispatch_async(dispatchQueue, ^{
                [self runJobWithParams:jobParamsDict];
            });
        }
        [jobParamsDict release];
    }
}

- (void) wait {
    dispatch_barrier_sync(dispatchQueue, ^{
        
    });
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
        
        dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        jobs = [[NSMutableArray alloc] initWithCapacity:10000];
        
        self.jobsCountLimit = maxJobsCount;
        self.jobsCount = 0;
        self.isPaused = NO;
    }
    return self;
}

- (void) dealloc {
    [jobs release];
    dispatch_release(dispatchQueue);
    
    [super dealloc];
}

+ (OPJobDispatcher *) disparcher {
    static OPJobDispatcher *instance  = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPJobDispatcher alloc] initWithMaxJobsCount:[OPConfig config].maxJobsCount];
    });
    return instance;
    
}

@end

/*
 
 NSOperationQueue *queue = [[NSOperationQueue alloc] init];
 [queue setMaxConcurrentOperationCount:10];
 NSOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(close) object:NULL];
 [queue addOperation:operation];
 
 */
