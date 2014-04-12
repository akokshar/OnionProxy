//
//  OPTorNode.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 09/02/14.
//
//

#import <Foundation/Foundation.h>
#import "OPObject.h"
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

@interface OPTorNode : OPObject {
    
}

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

@property (readonly) NSString *ip;
@property (readonly) NSUInteger orPort;
@property (readonly) NSUInteger dirPort;

@property (readonly) NSDate *lastUpdated;

//@property (readonly) OPRSAPublicKey *signingKey;
@property (readonly) OPRSAPublicKey *onionKey;

@property (readonly, getter = getIsHasLastDescriptor) BOOL isHasLastDescriptor;
- (void) prefetchDescriptor;

- (id) initWithParams:(NSDictionary *)nodeParams;
- (void) updateWithParams:(NSDictionary *)nodeParams;

- (void) cleanCachedInfo;

@end
