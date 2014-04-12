//
//  OPSessionKey.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 26/03/14.
//
//

#import "OPObject.h"

@interface OPSimmetricKey : OPObject {
    
}

@property (readonly, getter = getKeyData) NSData *keyData;

- (id) initWithLength:(NSUInteger)length;
- (NSData *) encryptData:(NSData *)data;
- (NSData *) decryptData:(NSData *)data;

@end
