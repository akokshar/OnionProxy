//
//  OPSHA256.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 23/04/14.
//
//

#import "OPSHA256.h"
#import <CommonCrypto/CommonDigest.h>

@interface OPSHA256() {
    CC_SHA256_CTX ctx;
}

@end

@implementation OPSHA256

- (void) updateWithData:(NSData *)data {
    CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
}

- (NSData *) digest {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX interimCtx;
    memcpy(&interimCtx, &ctx, sizeof(CC_SHA256_CTX));
    CC_SHA256_Final(digest, &interimCtx);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

- (id) init {
    self = [super init];
    if (self) {
        CC_SHA256_Init(&ctx);
    }
    return self;
}

+ (NSData *) digestOfData:(NSData *)data {
    OPSHA256 *sha256 = [[OPSHA256 alloc] init];
    [sha256 updateWithData:data];
    NSData *digest = [sha256 digest];
    [sha256 release];
    return digest;
}

+ (NSData *) digestOfText:(NSString *)text {
    return [OPSHA256 digestOfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}


@end
