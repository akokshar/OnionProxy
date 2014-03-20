//
//  OPTorNode.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 09/02/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"

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
@property (readonly) NSString *orPort;
@property (readonly) NSString *dirPort;

@property (readonly) NSDate *lastUpdated;

@property (readonly, getter = getIsHasLastDescriptor) BOOL isHasLastDescriptor;
- (void) retriveDescriptor;

- (id) initWithFingerprint:(NSData *)fingerprint descriptor:(NSData *)digest ip:(NSString *)ip orPort:(NSString *)orPort dirPort:(NSString *)dirPort flags:(NSString *)flags;
- (void) updateWithDescriptor:(NSData *)digest ip:(NSString *)ip orPort:(NSString *)orPort dirPort:(NSString *)dirPort flags:(NSString *)flags;
- (void) cleanCachedInfo;

@end
