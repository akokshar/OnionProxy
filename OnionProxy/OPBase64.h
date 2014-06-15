//
//  OPBase64.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 18/05/14.
//
//

#import "OPObject.h"

@interface OPBase64 : OPObject {
    
}

+ (NSData *) decodeString:(NSString *)str;
+ (NSString *) encodeData:(NSData *)data;

@end
