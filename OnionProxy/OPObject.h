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

- (NSData *) decodeBase64Str:(NSString *)str;
- (NSString *) hexStringFromData:(NSData *)data;

@end
