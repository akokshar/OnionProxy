//
//  OPConsensus.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 01/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"
#import "OPTorNode.h"

@interface OPConsensus : OPObject {
    
}

+ (OPConsensus *) consensus;

@property (readonly) NSString *version;
@property (readonly) NSString *flavor;

@property (readonly) NSDate *validAfter;
@property (readonly) NSDate *freshUntil;
@property (readonly) NSDate *validUntil;

@property (readonly) NSDate *lastUpdated;

@property (readonly, getter = getRandomV2DirNode) OPTorNode *randomV2DirNode;
@property (readonly, getter = getRandomExitNode) OPTorNode *randomExitNode;

@property (assign) IBOutlet NSTextField *tfNodesCount;
@property (assign) IBOutlet NSTextField *tfDirServersCount;
@property (assign) IBOutlet NSTextField *tfExitNodesCount;

@property (assign) IBOutlet NSTextField *tfCurrentOperation;

@end
