//
//  OPObject.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 02/03/14.
//
//

#import "OPObject.h"
#import <Security/Security.h>

@interface OPObject() {
    
}

@property (retain) NSString *name;

@end

@implementation OPObject

- (void) logMsg:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    printf("[%s] %s\n", (const char *)[self.name UTF8String], (const char *)[message UTF8String]);
    [message release];
    va_end(args);
}

- (NSData *) sha1DigestOfData:(NSData *)data {
    @synchronized(self) {
        SecTransformRef digestTransform = SecDigestTransformCreate(kSecDigestSHA1, 0, NULL);
        SecTransformSetAttribute(digestTransform, kSecTransformInputAttributeName, data, NULL);
        NSData *digestData = SecTransformExecute(digestTransform, NULL);
        CFRelease(digestTransform);
        
        return [digestData autorelease];
    }
}

- (NSData *) sha1DigestOfText:(NSString *)text {
    return [self sha1DigestOfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSData *) sha2DigestOfData:(NSData *)data digestLen:(NSUInteger)digestLen {
    @synchronized(self) {
        SecTransformRef digestTransform = SecDigestTransformCreate(kSecDigestSHA2, digestLen, NULL);
        SecTransformSetAttribute(digestTransform, kSecTransformInputAttributeName, data, NULL);
        NSData *digestData = SecTransformExecute(digestTransform, NULL);
        CFRelease(digestTransform);
        
        return [digestData autorelease];
    }
}

- (NSData *) sha2DigestOfText:(NSString *)text digestLen:(NSUInteger)digestLen {
    return [self sha2DigestOfData:[text dataUsingEncoding:NSUTF8StringEncoding] digestLen:digestLen];
}

//

- (NSData *) decodeBase64Str:(NSString *)str {
// Method hangs when called form multiple threads. WTF? @synchronized is here for that reason (and, just in case, in above methods).
//    @synchronized(self) {
//        SecTransformRef base64DecodeTransform = SecDecodeTransformCreate(kSecBase64Encoding, NULL);
//        SecTransformSetAttribute(base64DecodeTransform, kSecTransformInputAttributeName, [str dataUsingEncoding:NSUTF8StringEncoding], NULL);
//        NSData *data = SecTransformExecute(base64DecodeTransform, NULL);
//        CFRelease(base64DecodeTransform);
//        
//        return [data autorelease];
    
    // [NSData initWithBase64EncodedString] method is much faster then SecDecodeTransform. Also sync is not required
        return [[[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
//    }
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
