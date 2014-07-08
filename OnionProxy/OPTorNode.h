//
//  OPTorNode.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 09/02/14.
//
//

#import <Foundation/Foundation.h>
#import "OPTorDirectoryObject.h"
#import "OPRSAPublicKey.h"

extern NSString * const nodeFingerprintDataKey;
extern NSString * const nodeFingerprintStrKey;
extern NSString * const nodeDescriptorDataKey;
extern NSString * const nodeDescriptorStrKey;
extern NSString * const nodeIpStrKey;
extern NSString * const nodeOrPortStrKey;
extern NSString * const nodeDirPortStrKey;
extern NSString * const nodeFlagsStrKey;
extern NSString * const nodeVersionStrKey;
extern NSString * const nodeBandwidthStrKey;
extern NSString * const nodePolicyStrKey;

@class OPTorNode;

typedef enum {
    OPTorNodeDescriptorReadyEvent,
    OPTorNodeDescriptorUpdateInProgressEvent,
    OPTorNodeDescriptorUpdateFailedEvent
} OPTorNodeEvent;

@protocol OPTorNodeDelegate <NSObject>
- (void) node:(OPTorNode *)node event:(OPTorNodeEvent)event;
@end

@interface OPTorNode : OPTorDirectoryObject {
    
}

@property (assign) id<OPTorNodeDelegate>delegate;

@property (readonly) BOOL isValid;
@property (readonly) BOOL isNamed;
@property (readonly) BOOL isUnnamed;
@property (readonly) BOOL isRunning;
@property (readonly) BOOL isStable;
@property (readonly) BOOL isExit;
@property (readonly) BOOL isBadExit;
@property (readonly) BOOL isFast;
@property (readonly) BOOL isGuard;
@property (readonly) BOOL isAuthority;
@property (readonly) BOOL isV2Dir;
@property (readonly) BOOL isBadDirectory;
@property (readonly) BOOL isHSDir;

@property (readonly) NSString *ipStr;
@property (readonly) uint32_t ip;
@property (readonly) NSUInteger orPort;
@property (readonly) NSUInteger dirPort;

@property (readonly) NSDate *lastUpdated;

@property (readonly) OPRSAPublicKey *identKey;
@property (readonly) OPRSAPublicKey *onionKey;

- (void) prefetchDescriptor;
- (void) retainDescriptor;
- (void) releaseDescriptor;
- (void) clearCashedDescriptor;

- (id) initWithParams:(NSDictionary *)nodeParams;

@end
