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

NSUInteger const requiredReadyNodes = 16;

@interface OPTorDirectory() {
    OPConsensus *consensus;
    OPTorDirectoryViewController *viewController;
    
    NSMutableArray *torReadyNodes;
}

@property (assign) NSUInteger v2DirNodesIndex;
@property (retain, atomic) NSArray *v2DirNodesKeys;

@property (assign) NSUInteger torNodesIndex;
@property (retain, atomic) NSArray *torNodesKeys;

- (void) directoryInit;

- (void) prefetchTorNodeDescriptors;

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

    if (!self.v2DirNodesKeys && !consensus.nodes) {
        [self logMsg:@"No directory servers known (1)."];
        return NULL;
    }

    if ([self.v2DirNodesKeys count] == 0 || consensus.nodes.count == 0) {
        [self logMsg:@"No directory servers known (2)."];
        return NULL;
    }

    NSUInteger randomIndex = arc4random() % self.v2DirNodesKeys.count;
    return [consensus.nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:randomIndex]];

    OPTorNode *randomDirNode = NULL;

    @synchronized(self.v2DirNodesKeys) {
        NSUInteger lastIndex = self.v2DirNodesIndex;
        do {
            randomDirNode = [consensus.nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:self.v2DirNodesIndex]];
            self.v2DirNodesIndex++;
            if (self.v2DirNodesIndex >= self.v2DirNodesKeys.count) {
                self.v2DirNodesIndex = 0;
            }
        } while (!randomDirNode && lastIndex != self.v2DirNodesIndex);

        if (lastIndex == self.v2DirNodesIndex) {
            self.v2DirNodesKeys = [self arrayByShufflingArray:self.v2DirNodesKeys];
        }
        
        if (randomDirNode == NULL) {
            [self logMsg:@"Cant find directory server"];
        }
    }
    
    return randomDirNode;
}

- (OPTorNode *) getRandomRouter {
    OPTorNode *node = NULL;
    @synchronized(torReadyNodes) {
        if (torReadyNodes.count > 0) {
            node = [torReadyNodes objectAtIndex:0];
            [node retain];
            [torReadyNodes removeObjectAtIndex:0];
        }
    }

    [viewController setPreloadedDescriptorsCount:[torReadyNodes count]];
    
    return [node autorelease];
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

    [self prefetchTorNodeDescriptors];
}

- (void) prefetchTorNodeDescriptors {
    [self logMsg:@"Prefetching descriptors"];
    if (!self.torNodesKeys && self.torNodesKeys.count == 0) {
        return;
    }

    if (torReadyNodes.count >= requiredReadyNodes) {
        return;
    }
    
    for (NSUInteger i = torReadyNodes.count; i < requiredReadyNodes; i++) {
        if (self.torNodesIndex >= self.torNodesKeys.count) {
            self.torNodesIndex = 0;
            self.torNodesKeys = [self arrayByShufflingArray:self.torNodesKeys];
        }
        OPTorNode *node = [consensus.nodes objectForKey:[self.torNodesKeys objectAtIndex:self.torNodesIndex]];
        node.delegate = self;
        [node prefetchDescriptor];
        
        self.torNodesIndex++;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self prefetchTorNodeDescriptors];
    });

}

- (void) torNode:(OPTorNode *)node event:(OPTorNodeEvent)event {
    switch (event) {
        case OPTorNodeDescriptorReadyEvent: {
            @synchronized(torReadyNodes) {
                [torReadyNodes addObject:node];
//                [self logMsg:@"have %lu descriptors", (unsigned long)torReadyNodes.count];
            }

            [viewController setPreloadedDescriptorsCount:[torReadyNodes count]];
            
            if ([torReadyNodes count] >= requiredReadyNodes) {
                [self.delegate onNetworkReady];
                [self logMsg:@"onNetworkReady"];
            }
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

- (void) directoryInit {
    [self logMsg:@"INIT DIRECTORY"];
    consensus = [[OPConsensus alloc] init];
    consensus.delegate = self;
  
    viewController = [[OPTorDirectoryViewController alloc] initWithNibName:@"OPTorDirectory" bundle:NULL];

    self.v2DirNodesKeys = NULL;
    self.v2DirNodesIndex = 0;
    
    self.torNodesKeys = NULL;
    self.torNodesIndex = 0;
    
    torReadyNodes = [[NSMutableArray alloc] initWithCapacity:requiredReadyNodes * 2];
}

- (void) dealloc {
    [torReadyNodes release];
    
    [viewController release];
    
    self.v2DirNodesKeys = NULL;
    self.torNodesKeys = NULL;
    
    [super dealloc];
}

+ (OPTorDirectory *) directory {
    return [[OPTorDirectory alloc] init];
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

+ (OPTorNode *) getRandomRouter {
    return [OPTorDirectory directory].getRandomRouter;
}

+ (OPTorNode *) getRandomDirectory {
    return [OPTorDirectory directory].getRandomDirectory;
}

@end
