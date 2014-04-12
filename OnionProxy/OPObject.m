//
//  OPObject.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 02/03/14.
//
//

#import "OPObject.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

@interface OPObject() {
    
}

@property (retain) NSString *name;

@end

@implementation OPObject

- (void) logMsg:(NSString *)format, ... {
    static int i = 0;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    printf("[%i] %s\n", i++, (const char *)[message UTF8String]);
    [message release];
    va_end(args);
}

- (NSData *) sha1DigestOfData:(NSData *)data {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];

    // bellow realization hangs if called by multiple threads. Even thre is no conflicts
//    @synchronized(self) {
//        SecTransformRef digestTransform = SecDigestTransformCreate(kSecDigestSHA1, 0, NULL);
//        SecTransformSetAttribute(digestTransform, kSecTransformInputAttributeName, data, NULL);
//        NSData *digestData = SecTransformExecute(digestTransform, NULL);
//        CFRelease(digestTransform);
//        
//        return [digestData autorelease];
//    }
}

- (NSData *) sha1DigestOfText:(NSString *)text {
    return [self sha1DigestOfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSData *) sha256DigestOfData:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];

//    @synchronized(self) {
//        SecTransformRef digestTransform = SecDigestTransformCreate(kSecDigestSHA2, 256, NULL);
//        SecTransformSetAttribute(digestTransform, kSecTransformInputAttributeName, data, NULL);
//        NSData *digestData = SecTransformExecute(digestTransform, NULL);
//        CFRelease(digestTransform);
//        
//        return [digestData autorelease];
//    }
}

- (NSData *) sha256DigestOfText:(NSString *)text {
    return [self sha256DigestOfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

//

- (NSData *) decodeBase64Str:(NSString *)str {
// Method hangs when called form multiple threads. WTF? @synchronized is here for that reason (and, just in case, in above methods).
//    @synchronized(self) {
//        SecTransformRef base64DecodeTransform = SecDecodeTransformCreate(kSecBase64Encoding, NULL);
//        SecTransformSetAttribute(base64DecodeTransform, kSecTransformInputAttributeName, [str dataUsingEncoding:NSUTF8StringEncoding], NULL);
//        NSData *data = SecTransformExecute(base64DecodeTransform, NULL);
//        CFRelease(base64DecodeTransform);
//        return [data autorelease];
//    
//    // [NSData initWithBase64EncodedString] method is much faster then SecDecodeTransform. Also sync is not required
//    }
    return [[[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
}

- (NSString *) hexStringFromData:(NSData *)data {
    NSMutableString *hexString = [[NSMutableString alloc] initWithCapacity:[data length] * 2];
    const unsigned char *bytes = [data bytes];
    for (int i = 0; i < [data length]; i++) {
        [hexString appendFormat:@"%02X", bytes[i]];
    }
    
    return [hexString autorelease];
}


@end
