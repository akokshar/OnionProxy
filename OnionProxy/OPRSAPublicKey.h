//
//  OPPublicKey.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/02/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"

@interface OPRSAPublicKey : OPObject {
    
}

@property (readonly) NSData *digest;
@property (readonly, getter = getDigestHexString) NSString *digestHexString;

/// length in bytes
@property (readonly, getter = getKeyLength) NSUInteger keyLength;

/// padding len (OAEP)
@property (readonly) NSUInteger padLength;

- (id) initWithBase64DerEncodingStr:(NSString *)keyEncoding;

- (BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDataDigest:(NSData *)digest;
- (NSData *) encryptData:(NSData *)data;

@end
