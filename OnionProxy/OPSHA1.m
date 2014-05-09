//
//  OPSHA1.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 23/04/14.
//
//

#import "OPSHA1.h"
#import <CommonCrypto/CommonDigest.h>

NSUInteger const sha1DigestLen = CC_SHA1_DIGEST_LENGTH;

@interface OPSHA1() {
    CC_SHA1_CTX ctx;
}

@end

@implementation OPSHA1

- (void) updateWithData:(NSData *)data {
    CC_SHA1_Update(&ctx, data.bytes, (CC_LONG)data.length);
}

- (NSData *) digest {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_CTX interimCtx;
    memcpy(&interimCtx, &ctx, sizeof(CC_SHA1_CTX));
    CC_SHA1_Final(digest, &interimCtx);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

- (id) init {
    self = [super init];
    if (self) {
        CC_SHA1_Init(&ctx);
    }
    return self;
}

+ (NSData *) digestOfData:(NSData *)data {
    OPSHA1 *sha1 = [[OPSHA1 alloc] init];
    [sha1 updateWithData:data];
    NSData *digest = [sha1 digest];
    [sha1 release];
    return digest;
}

+ (NSData *) digestOfText:(NSString *)text {
    return [OPSHA1 digestOfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSUInteger) digestLen {
    return CC_SHA1_DIGEST_LENGTH;
}

@end
