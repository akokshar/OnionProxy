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

@property (readonly, getter = getDigestHexString) NSString *digestHexString;

- (id) initWithBase64DerEncodingStr:(NSString *)keyEncoding;

-(BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDataDigest:(NSData *)digest;

@end
