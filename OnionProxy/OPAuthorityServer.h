//
//  OPAuthorityServer.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 15/02/14.
//
//

#import <Foundation/Foundation.h>

#import "OPTorDirectoryObject.h"

@interface OPAuthorityServer : OPTorDirectoryObject {
    
}

@property (readonly, getter = getIp) NSString *ip;
@property (readonly, getter = getDirPort) NSUInteger dirPort;
@property (readonly, getter = getNick) NSString *nick;

-(id) initWithConfigIndex:(NSUInteger)index;

- (BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDigest:(NSData *)digest;

@end
