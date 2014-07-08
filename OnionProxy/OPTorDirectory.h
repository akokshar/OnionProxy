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

@interface OPTorDirectory : OPObject <OPConsensusDelegate, OPTorNodeDelegate> {
    
}

@property (retain) id <OPDirectoryDelegate> delegate;
@property (readonly, getter = getView) NSView *view;

+ (OPTorDirectory *) directory;

/** 
 * Provide random TOR node with descriptor loaded. Guaranteed not to return NULL node;
 * Caller have to retaing returned object in order to keep descriptor.
 */
- (void) getRandomRouterAsync:(void (^)(OPTorNode *node))completionHandler;

/**
 * Return random cache server
 */
- (OPTorNode *) getRandomDirectory;
+ (OPTorNode *) getRandomDirectory;

/**
 * Provide random Cache node with descriptor loaded. Guaranteed not to return NULL node;
 * Caller have to retaing returned object in order to keep descriptor.
 */
- (void) getRandomDirRouterAsync:(void (^)(OPTorNode *node))completionHandler;


@end
