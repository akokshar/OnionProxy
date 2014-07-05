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
    OPConsensusEventNodeAdded,
    OPConsensusEventNodeDeleted
} OPConsensusNodeEvent;

@protocol OPConsensusDelegate <NSObject>
- (void) onConsensusUpdatedEvent;
- (void) consensusEvent:(OPConsensusNodeEvent)event forNode:(OPTorNode *)node;
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
