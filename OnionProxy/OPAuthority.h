//
//  OPAuthority.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/02/14.
//
//

#import <Foundation/Foundation.h>

#import "OPTorDirectoryObject.h"
#import "OPAuthority.h"
#import "OPAuthorityServer.h"

@interface OPAuthority : OPTorDirectoryObject

+ (OPAuthority *) authority;

@property (readonly, getter = getCount) NSUInteger count;
@property (readonly, getter = getRandomServer) OPAuthorityServer *randomServer;

- (BOOL) verifyBase64SignatureStr:(NSString *)signatureStr ofServerWithIdentDigest:(NSString *)identDigest forDigest:(NSData *)digest;

@end
