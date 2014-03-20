//
//  OPObject.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 02/03/14.
//
//

#import <Foundation/Foundation.h>

@interface OPObject : NSObject {
    
}

- (void) logMsg:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

- (NSData *) sha1DigestOfData:(NSData *)data;
- (NSData *) sha1DigestOfText:(NSString *)text;
- (NSData *) sha2DigestOfData:(NSData *)data digestLen:(NSUInteger)digestLen;
- (NSData *) sha2DigestOfText:(NSString *)text digestLen:(NSUInteger)digestLen;

- (NSData *) decodeBase64Str:(NSString *)str;

- (NSString *) hexStringFromData:(NSData *)data;

@end
