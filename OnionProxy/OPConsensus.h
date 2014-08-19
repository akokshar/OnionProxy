//
//  OPConsensus.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 01/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPTorDirectoryObject.h"
#import "OPTorNode.h"

@class OPConsensus;

typedef enum {
    /// sent after node was added
    OPConsensusEventNodeAdded,
    /// sent just before deleting node
    OPConsensusEventNodeWillDelete
} OPConsensusNodeEvent;

@protocol OPConsensusDelegate <NSObject>
- (void) onConsensusUpdatedEvent;
- (void) consensusEvent:(OPConsensusNodeEvent)event forNodeWithKey:(id)nodeKey;
@end

@interface OPConsensus : OPTorDirectoryObject {
    
}

@property (retain) id <OPConsensusDelegate> delegate;

@property (readonly) NSString *version;
@property (readonly) NSString *flavor;

@property (readonly) NSDate *validAfter;
@property (readonly) NSDate *freshUntil;
@property (readonly) NSDate *validUntil;

@property (readonly, getter = getNodes) NSDictionary *nodes;

@end
