//
//  OPNodesManager.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 27/04/14.
//
//

#import "OPTorDirectory.h"
#import "OPTorDirectoryViewController.h"
#import "OPConsensus.h"

NSUInteger const torDescriptorsReadyMinimum = 8;

@interface OPTorDirectory() {
    dispatch_queue_t torNodeRequestQueue;

    NSMutableArray *readyRouters;
    NSUInteger readyCacheCount;
    dispatch_semaphore_t readyRouterSemaphore;
    dispatch_semaphore_t readyCacheSemaphore;

    OPConsensus *consensus;
    OPTorDirectoryViewController *viewController;
}

@property (assign) NSUInteger v2DirNodesIndex;
@property (retain, atomic) NSArray *v2DirNodesKeys;

@property (assign) NSUInteger torNodesIndex;
@property (retain, atomic) NSArray *torNodesKeys;

- (void) directoryInit;

- (void) prefetchDescriptors;

- (void) shuffleArray:(NSMutableArray *)array;
- (NSArray *) arrayByShufflingArray:(NSArray *)array;

@end

@implementation OPTorDirectory

@synthesize view;

- (NSView *) getView {
    if (viewController) {
        return viewController.view;
    }
    return NULL;
}

@synthesize torNodesKeys;
@synthesize v2DirNodesKeys = _v2DirNodesKeys;

- (OPTorNode *) getRandomDirectory {
    if ([self.v2DirNodesKeys count] == 0) {
        [self logMsg:@"No directory servers known"];
        return NULL;
    }

    NSUInteger randomIndex = arc4random() % self.v2DirNodesKeys.count;
    return [consensus.nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:randomIndex]];
}

+ (OPTorNode *) getRandomDirectory {
    return [OPTorDirectory directory].getRandomDirectory;
}

- (void) getRandomCacheAsync:(void (^)(OPTorNode *node))completionHandler {
    dispatch_async(torNodeRequestQueue, ^{
        dispatch_semaphore_wait(readyCacheSemaphore, DISPATCH_TIME_FOREVER);
        OPTorNode *readyNode = NULL;

        @synchronized(readyRouters) {
            for (NSInteger i = [readyRouters count] - 1; i >= 0; i--) {
                readyNode = [readyRouters objectAtIndex:i];
                if (readyNode.isV2Dir) {
                    [readyNode retain];
                    [readyRouters removeObjectAtIndex:i];
                }
            }
        }
        [viewController setPreloadedDescriptorsCount:[readyRouters count]];

        readyCacheCount--;

        completionHandler(readyNode);
        [readyNode releaseDescriptor];
        [readyNode release];

        [self prefetchDescriptors];
    });
}

- (void) getRandomRouterAsync:(void (^)(OPTorNode *node))completionHandler {
    dispatch_async(torNodeRequestQueue, ^{
        dispatch_semaphore_wait(readyRouterSemaphore, DISPATCH_TIME_FOREVER);
        OPTorNode *readyNode = NULL;
        BOOL isHaveCache = (dispatch_semaphore_wait(readyCacheSemaphore, DISPATCH_TIME_NOW) == 0);

        @synchronized(readyRouters) {
            readyNode = [readyRouters lastObject];
            [readyNode retain];
            [readyRouters removeLastObject];
        }
        [viewController setPreloadedDescriptorsCount:[readyRouters count]];

        if (isHaveCache) {
            if (readyNode.isV2Dir) {
                readyCacheCount--;
            }
            else {
                dispatch_semaphore_signal(readyCacheSemaphore);
            }
        }

        completionHandler(readyNode);
        [readyNode releaseDescriptor];
        [readyNode release];

        [self prefetchDescriptors];
    });
}

- (void) prefetchDescriptors {
    if (!self.torNodesKeys && self.torNodesKeys.count == 0) {
        return;
    }

    if (readyRouters.count < torDescriptorsReadyMinimum) {
        [self logMsg:@"Prefetching descriptors"];
        for (NSUInteger i = readyRouters.count; i < torDescriptorsReadyMinimum; i++) {
            if (self.torNodesIndex >= self.torNodesKeys.count) {
                self.torNodesIndex = 0;
                self.torNodesKeys = [self arrayByShufflingArray:self.torNodesKeys];
            }
            OPTorNode *node = [consensus.nodes objectForKey:[self.torNodesKeys objectAtIndex:self.torNodesIndex]];
            node.delegate = self;
            [node prefetchDescriptor];
            
            self.torNodesIndex++;
        }
    }

    if (readyCacheCount < torDescriptorsReadyMinimum) {
        for (NSUInteger i = readyCacheCount; i < torDescriptorsReadyMinimum; i++) {
            if (self.v2DirNodesIndex >= self.v2DirNodesKeys.count) {
                self.v2DirNodesIndex = 0;
                self.v2DirNodesKeys = [self arrayByShufflingArray:self.v2DirNodesKeys];
            }
            OPTorNode *node = [consensus.nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:self.v2DirNodesIndex]];
            node.delegate = self;
            [node prefetchDescriptor];

            self.v2DirNodesIndex++;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self prefetchDescriptors];
    });
}

- (void) node:(OPTorNode *)node event:(OPTorNodeEvent)event {
    switch (event) {
        case OPTorNodeDescriptorReadyEvent: {
            @synchronized(readyRouters) {
                [readyRouters addObject:node];
            }
            dispatch_semaphore_signal(readyRouterSemaphore);
            if (node.isV2Dir) {
                readyCacheCount++;
                dispatch_semaphore_signal(readyCacheSemaphore);
            }
            [viewController setPreloadedDescriptorsCount:[readyRouters count]];
        } break;
            
        default:
            break;
    }
}

- (void) shuffleArray:(NSMutableArray *)array {
    if (array == NULL || [array count] == 0) {
        return;
    }

    for (NSUInteger i = 0; i < [array count] - 1; i++) {
        NSUInteger j = arc4random() % [array count];
        [array exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

- (NSArray *) arrayByShufflingArray:(NSArray *)array {
    if (array == NULL || [array count] == 0) {
        return array;
    }
    
    NSMutableArray *tempArray = [NSMutableArray arrayWithArray:array];
    for (NSUInteger i = 0; i < [tempArray count] - 1; i++) {
        NSUInteger j = arc4random() % [tempArray count];
        [tempArray exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    return tempArray;
}

- (void) consensusEvent:(OPConsensusNodeEvent)event forNode:(OPTorNode *)node {
    switch (event) {
        case OPConsensusEventNodeAdded: {

        } break;

        case OPConsensusEventNodeDeleted: {

        } break;
    }
}

- (void) onConsensusUpdatedEvent {

    [viewController setConsensusValidAfter:consensus.validAfter];
    [viewController setConsensusValidUntil:consensus.validUntil];
    [viewController setConsensusFreshUntil:consensus.freshUntil];

    [viewController setTotalNodesCount:consensus.nodes.count];

    @synchronized(self.v2DirNodesKeys) {
        NSSet *v2DirNodesSet = [consensus.nodes keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
            OPTorNode *node = (OPTorNode *)obj;
            return node.isV2Dir && node.isRunning;
        }];

        self.v2DirNodesKeys = [self arrayByShufflingArray:[v2DirNodesSet allObjects]];
        self.v2DirNodesIndex = 0;

        [viewController setDirNodesCount:self.v2DirNodesKeys.count];
    }

    @synchronized(self.torNodesKeys) {
        NSSet *torNodesSet = [consensus.nodes keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
            OPTorNode *node = (OPTorNode *)obj;
            return node.isFast && node.isRunning;
        }];

        self.torNodesKeys = [self arrayByShufflingArray:[torNodesSet allObjects]];
        self.torNodesIndex = 0;

        [viewController setTorFastNodesCount:self.torNodesKeys.count];
    }

    [self logMsg:@"Nodes updated."];

    [self prefetchDescriptors];
}

- (void) directoryInit {
    [self logMsg:@"INIT DIRECTORY"];
    consensus = [[OPConsensus alloc] init];
    consensus.delegate = self;
  
    viewController = [[OPTorDirectoryViewController alloc] initWithNibName:@"OPTorDirectory" bundle:NULL];

    self.v2DirNodesKeys = NULL;
    self.v2DirNodesIndex = 0;
    
    self.torNodesKeys = NULL;
    self.torNodesIndex = 0;

    torNodeRequestQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);

    readyRouters = [[NSMutableArray alloc] init];
    readyCacheCount = 0;
    readyRouterSemaphore = dispatch_semaphore_create(0);
    readyCacheSemaphore= dispatch_semaphore_create(0);
}

- (void) dealloc {
    [viewController release];

    dispatch_release(torNodeRequestQueue);

    [readyRouters release];
    dispatch_release(readyRouterSemaphore);
    dispatch_release(readyCacheSemaphore);
    
    self.v2DirNodesKeys = NULL;
    self.torNodesKeys = NULL;

    [super dealloc];
}

+ (OPTorDirectory *) directory {
    return [OPTorDirectory instance];
}

+ (OPTorDirectory *) instance {
    static OPTorDirectory *instance = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
        [instance directoryInit];
    });
    return instance;
}

- (id) init {
    return self;
}

+ (id) alloc {
    return [OPTorDirectory allocWithZone:NULL];
}

+ (id) allocWithZone:(NSZone *)zone {
    return [OPTorDirectory instance];
}

- (id) copyWithZone:(NSZone *)zone {
    return self;
}

- (id) retain {
    return self;
}

- (NSUInteger) retainCount {
    return NSUIntegerMax;  //denotes an object that cannot be released
}

- (oneway void) release {
}

- (id) autorelease {
    return self;
}

@end
