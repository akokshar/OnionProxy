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
 * Return tor node with descriptor loaded. 
 * Caller have to retaing returned object in order to keep descriptor.
 */
- (OPTorNode *) getRandomRouter;
+ (OPTorNode *) getRandomRouter;

/**
 * Return random cache server
 */
- (OPTorNode *) getRandomDirectory;
+ (OPTorNode *) getRandomDirectory;


@end
