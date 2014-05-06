//
//  OPSHA1.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 23/04/14.
//
//

#import "OPObject.h"

@interface OPSHA1 : OPObject {
    
}

- (void) updateWithData:(NSData *)data;
- (NSData *) digest;

+ (NSData *) digestOfData:(NSData *)data;
+ (NSData *) digestOfText:(NSString *)text;
+ (NSUInteger) digestLen;

@end
