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

@property (retain) NSMutableArray *v2DirNodesKeys;
@property (retain) NSMutableArray *torNodesKeys;
@property (retain) NSMutableArray *exitNodesKeys;
@property (retain) NSMutableDictionary *portToExitNodes;

- (void) directoryInit;

- (OPTorNode *) getRandomDirectory;
- (void) prefetchDescriptors;

- (void) shuffleArray:(NSMutableArray *)array;

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

- (void) getRandomExitNoteToPort:(uint16)port async:(void (^)(OPTorNode *node))completionHandler {
    
}

- (void) getRandomCacheAsync:(void (^)(OPTorNode *node))completionHandler {
    dispatch_async(torNodeRequestQueue, ^{
        dispatch_semaphore_wait(readyCacheSemaphore, DISPATCH_TIME_FOREVER);
        OPTorNode *readyNode = NULL;

        @synchronized(readyRouters) {
            for (NSInteger i = [readyRouters count] - 1; (i >= 0) && (readyNode == NULL); i--) {
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
    });

    [self prefetchDescriptors];
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
    });

    [self prefetchDescriptors];
}

- (void) prefetchDescriptors {
    if (!self.torNodesKeys) {
        return;
    }

    void (^completionHandler)(OPTorNode *) = ^void(OPTorNode *node) {
        if (node) {
            @synchronized(readyRouters) {
                [readyRouters addObject:node];
            }
            dispatch_semaphore_signal(readyRouterSemaphore);
            if (node.isV2Dir) {
                readyCacheCount++;
                dispatch_semaphore_signal(readyCacheSemaphore);
            }
            [viewController setPreloadedDescriptorsCount:[readyRouters count]];
        }
    };

    if ((readyRouters.count < torDescriptorsReadyMinimum) && ([self.torNodesKeys count] > 0)) {
        for (NSUInteger i = readyRouters.count; i < torDescriptorsReadyMinimum; i++) {
            NSUInteger r = arc4random() % self.torNodesKeys.count;
            OPTorNode *node = [consensus.nodes objectForKey:[self.torNodesKeys objectAtIndex:r]];
            node.delegate = self;
            [node prefetchDescriptorAsyncWhenDoneCall:completionHandler];
        }
    }

    if ((readyCacheCount < torDescriptorsReadyMinimum) && ([self.v2DirNodesKeys count] > 0)) {
        for (NSUInteger i = readyCacheCount; i < torDescriptorsReadyMinimum; i++) {
            NSUInteger r = arc4random() % self.v2DirNodesKeys.count;
            OPTorNode *node = [consensus.nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:r]];
            node.delegate = self;
            [node prefetchDescriptorAsyncWhenDoneCall:completionHandler];
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self prefetchDescriptors];
    });
}

- (void) testFetchOneDescriptor {
    void (^completionHandler)(OPTorNode *) = ^void(OPTorNode *node) {
        if (node) {
            @synchronized(readyRouters) {
                [readyRouters addObject:node];
            }
            dispatch_semaphore_signal(readyRouterSemaphore);
            if (node.isV2Dir) {
                readyCacheCount++;
                dispatch_semaphore_signal(readyCacheSemaphore);
            }
            [viewController setPreloadedDescriptorsCount:[readyRouters count]];
        }
    };

    NSUInteger r = arc4random() % self.v2DirNodesKeys.count;
    OPTorNode *node = [consensus.nodes objectForKey:[self.torNodesKeys objectAtIndex:r]];
    node.delegate = self;
    [node prefetchDescriptorAsyncWhenDoneCall:completionHandler];
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

    @synchronized(array) {
        for (NSUInteger i = 0; i < [array count] - 1; i++) {
            NSUInteger j = arc4random() % [array count];
            [array exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
    }
}

- (void) consensusEvent:(OPConsensusNodeEvent)event forNodeWithKey:(id)nodeKey {
    OPTorNode *node = [consensus.nodes objectForKey:nodeKey];

    if (node == NULL) {
        [self logMsg:@"consensusEvent 'cant find node'"];
        return;
    }

    switch (event) {
        case OPConsensusEventNodeAdded: {
            if (node.isExit) {
                @synchronized(self.exitNodesKeys) {
                    [self.exitNodesKeys addObject:nodeKey];
                }
            }

            if (node.isV2Dir) {
                @synchronized(self.v2DirNodesKeys) {
                    [self.v2DirNodesKeys addObject:nodeKey];
                }
            }

            @synchronized(self.torNodesKeys) {
                [self.torNodesKeys addObject:nodeKey];
            }

        } break;

        case OPConsensusEventNodeWillDelete: {
            @synchronized(self.exitNodesKeys) {
                [self.exitNodesKeys removeObject:nodeKey];
            }

            @synchronized(self.v2DirNodesKeys) {
                [self.v2DirNodesKeys removeObject:nodeKey];
            }
            
            @synchronized(self.torNodesKeys) {
                [self.torNodesKeys removeObject:nodeKey];
            }

        } break;
    }
}

- (void) onConsensusUpdatedEvent {

    [viewController setConsensusValidAfter:consensus.validAfter];
    [viewController setConsensusValidUntil:consensus.validUntil];
    [viewController setConsensusFreshUntil:consensus.freshUntil];

    [viewController setTotalNodesCount:consensus.nodes.count];
    [viewController setExitNodesCount:self.exitNodesKeys.count];
    [viewController setDirNodesCount:self.v2DirNodesKeys.count];

    @synchronized(self.portToExitNodes) {
        [self.portToExitNodes removeAllObjects];
    }

    [self logMsg:@"Directory updated."];

    [self prefetchDescriptors];
}

- (void) directoryInit {
    [self logMsg:@"INIT DIRECTORY"];
    consensus = [[OPConsensus alloc] init];
    consensus.delegate = self;
  
    viewController = [[OPTorDirectoryViewController alloc] initWithNibName:@"OPTorDirectory" bundle:NULL];

    self.v2DirNodesKeys = [NSMutableArray array];
    self.torNodesKeys = [NSMutableArray array];
    self.exitNodesKeys = [NSMutableArray array];
    self.portToExitNodes = [NSMutableDictionary dictionary];

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
    self.exitNodesKeys = NULL;
    self.portToExitNodes = NULL;

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
