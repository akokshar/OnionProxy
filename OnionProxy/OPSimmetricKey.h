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

@property (readonly) NSUInteger keyLength;
@property (readonly, getter = getKeyData) NSData *keyData;

- (id) initWithData:(NSData *)data;

- (NSData *) encryptData:(NSData *)data;
- (void) inplaceEncryptData:(NSMutableData *)data;

- (NSData *) decryptData:(NSData *)data;
- (void) inplaceDecryptData:(NSMutableData *)data;

@end
