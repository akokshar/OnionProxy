//
//  OPSHA1.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 23/04/14.
//
//

#import "OPObject.h"

extern NSUInteger const sha1DigestLen;

@interface OPSHA1 : OPObject <NSCopying> {
    
}

- (void) updateWithData:(NSData *)data;
- (NSData *) digest;

+ (NSData *) digestOfData:(NSData *)data;
+ (NSData *) digestOfText:(NSString *)text;
+ (NSUInteger) digestLen;

@end
