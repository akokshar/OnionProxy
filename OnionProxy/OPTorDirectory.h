//
//  OPTorNodesDirectory.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 27/04/14.
//
//

#import "OPObject.h"
#import "OPTorNode.h"
#import "OPConsensus.h"

@protocol OPDirectoryDelegate <NSObject>
- (void) onNetworkReady;
@end

@interface OPTorDirectory : OPObject <OPConsensusDelegate> {
    
}

@property (retain) id <OPDirectoryDelegate> delegate;
@property (readonly, getter = getView) NSView *view;

+ (OPTorDirectory *) directory;

- (void) getRandomExitNodeToPort:(uint16)port async:(void (^)(OPTorNode *node))completionHandler;

/** 
 * Provide random TOR node with descriptor loaded. Guaranteed not to return NULL node;
 * Caller have to call retainDescriptor on returned object in order to keep descriptor.
 * Release descriptor with releaseDescriptor when done;
 */
- (void) getRandomRouterAsync:(void (^)(OPTorNode *node))completionHandler;

/**
 * Return random cache server
 */
+ (OPTorNode *) getRandomDirectory;

/**
 * Provide random Cache node with descriptor loaded. Guaranteed not to return NULL node;
 * Caller have to call retainDescriptor on returned object in order to keep descriptor.
 * Release descriptor with releaseDescriptor when done;
 */
- (void) getRandomCacheAsync:(void (^)(OPTorNode *node))completionHandler;

- (void) testFetchOneDescriptor;


@end
