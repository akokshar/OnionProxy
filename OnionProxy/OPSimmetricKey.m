//
//  OPSessionKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 26/03/14.
//
//

#import "OPSimmetricKey.h"
#import <CommonCrypto/CommonCryptor.h>

#define AES_KEY_LEN 16

@interface OPSimmetricKey() {
    CCCryptorRef cryptor;
}

@property (retain) NSData *keyData;
//@property (retain) NSMutableData *ivData;

- (void) initializeWithKeyData:(NSData *)key ivData:(NSData *)iv;
- (NSData *) randomDataOfLen:(NSUInteger)length;
- (NSData *) ccCryptData:(NSData *)data;
@end

@implementation OPSimmetricKey

@synthesize keyLength;

- (NSUInteger) getKeyLength {
    return self.keyData.length;
}

//@synthesize ivData;

@synthesize keyData;

- (NSData *) encryptData:(NSData *)data {
    return [self ccCryptData:data];
}

- (void) inplaceEncryptData:(NSMutableData *)data {
    [data setData:[self ccCryptData:data]];
}

- (NSData *) decryptData:(NSData *)data {
    return [self ccCryptData:data];
}

- (void) inplaceDecryptData:(NSMutableData *)data {
    [data setData:[self ccCryptData:data]];
    return;
}

- (NSData *) ccCryptData:(NSData *)data {
    NSMutableData * buffer = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    size_t bytesEncrypted = 0;

    CCCryptorStatus cryptStatus;
    cryptStatus = CCCryptorUpdate(cryptor,
                                  data.bytes,
                                  data.length,
                                  buffer.mutableBytes,
                                  buffer.length,
                                  &bytesEncrypted);

    if (cryptStatus != kCCSuccess){
        [self logMsg:@"AESCryptor failed to crypt data"];
    }

    [buffer setLength:bytesEncrypted];
    return [NSData dataWithData:buffer];
}

- (NSData *) randomDataOfLen:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return data;
}

- (void) initializeWithKeyData:(NSData *)key ivData:(NSData *)iv {
    self.keyData = key;
//    self.ivData = [iv mutableCopy];

    CCCryptorStatus cryptStatus;
    cryptStatus = CCCryptorCreateWithMode(kCCEncrypt,
                                          kCCModeCTR,
                                          kCCAlgorithmAES128,
                                          ccNoPadding,
                                          iv.bytes,
                                          self.keyData.bytes,
                                          self.keyData.length,
                                          NULL,
                                          0,
                                          0,
                                          kCCModeOptionCTR_BE,
                                          &cryptor);

    if (cryptStatus != kCCSuccess) {
        [self logMsg:@"Cant initialize Cryptor"];
    }
}

- (id) init {
    self = [super init];
    if (self) {
        unsigned char ivec[AES_KEY_LEN];
        memset(ivec, 0, AES_KEY_LEN);
        [self initializeWithKeyData:[self randomDataOfLen:AES_KEY_LEN] ivData:[NSData dataWithBytes:ivec length:AES_KEY_LEN]];
    }
    return self;
}

- (id) initWithKeyData:(NSData *)key ivData:(NSData *)iv {
    self = [super init];
    if (self) {
        [self initializeWithKeyData:key ivData:iv];
    }
    return self;
}

- (id) initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        unsigned char ivec[AES_KEY_LEN];
        memset(ivec, 0, AES_KEY_LEN);
        [self initializeWithKeyData:data ivData:[NSData dataWithBytes:ivec length:AES_KEY_LEN]];
    }
    return self;
}

- (void) dealloc {
    CCCryptorRelease(cryptor);
    self.keyData = NULL;
//    self.ivData = NULL;

    [super dealloc];
}

@end
