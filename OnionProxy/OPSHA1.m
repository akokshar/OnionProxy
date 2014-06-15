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

}

@property (readwrite, getter = getCtxt, setter = setCtxt:) CC_SHA1_CTX *ctxt;

@end

@implementation OPSHA1

@synthesize ctxt = _ctxt;

- (CC_SHA1_CTX *) getCtxt {
    @synchronized(self) {
        if (_ctxt == NULL) {
            _ctxt = malloc(sizeof(CC_SHA1_CTX));
            CC_SHA1_Init(_ctxt);
        }
    }
    return _ctxt;
}

- (void) setCtxt:(CC_SHA1_CTX *)ctxt {
    @synchronized(self) {
        if (_ctxt) {
            free(_ctxt);
        }
        _ctxt = ctxt;
    }
}

- (void) updateWithData:(NSData *)data {
    CC_SHA1_Update(self.ctxt, data.bytes, (CC_LONG)data.length);
}

- (NSData *) digest {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1_CTX interimCtx;
    memcpy(&interimCtx, self.ctxt, sizeof(CC_SHA1_CTX));
    
    CC_SHA1_Final(digest, &interimCtx);
    
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

- (id) copyWithZone:(NSZone *)zone {
    OPSHA1 *copyObj = [[OPSHA1 alloc] init];
    CC_SHA1_CTX *copyCtxt = malloc(sizeof(CC_SHA1_CTX));
    
    memcpy(copyCtxt, self.ctxt, sizeof(CC_SHA1_CTX));
    copyObj.ctxt = copyCtxt;
    
    return copyObj;
}

- (id) init {
    self = [super init];
    if (self) {

    }
    return self;
}

- (void) dealloc {
    self.ctxt = NULL;
    [super dealloc];
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
