//
//  OPSessionKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 26/03/14.
//
//

// if nothing defined SecTransform will be used (no AES counter mode)
#define AES_USE_OSSL
//#define AES_USE_CC // no AES counter mode

#import "OPSimmetricKey.h"

#ifdef AES_USE_OSSL
    #import <openssl/aes.h>
#else
    #import <Security/Security.h>
#endif

#define AES_KEY_LEN 16

@interface OPSimmetricKey() {
    
}

#ifndef AES_USE_OSSL
@property (readonly, getter = getSecKey) SecKeyRef secKey;
#endif

- (NSData *) randomDataOfLen:(NSUInteger)length;
- (NSData *) osslCryptData:(NSData *)data;
- (void) osslInplaceCryptData:(NSMutableData *)data;

@end

@implementation OPSimmetricKey

@synthesize keyLength = _keyLength;

@synthesize keyData = _keyData;

- (NSData *) getKeyData {
    return _keyData;
}

#ifndef AES_USE_OSSL
@synthesize secKey = _secKey;

- (SecKeyRef) getSecKey {
    @synchronized(self) {
        if (!_secKey) {
            if (_keyData) {
                CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                
                CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeAES);
                CFDictionarySetValue(parameters, kSecAttrKeyClass, kSecAttrKeyClassSymmetric);
             
                NSUInteger keyLen = _keyLength * 8;
                CFNumberRef len = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &keyLen);
                CFDictionarySetValue(parameters, kSecAttrKeySizeInBits, len);
                CFRelease(len);

                _secKey = SecKeyCreateFromData(parameters, (CFDataRef)_keyData, NULL);
            }
            else {
                CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

                CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeAES);
                CFDictionarySetValue(parameters, kSecAttrKeyClass, kSecAttrKeyClassSymmetric);

                NSUInteger keyLen = _keyLength * 8;
                CFNumberRef len = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &keyLen);
                CFDictionarySetValue(parameters, kSecAttrKeySizeInBits, len);
                CFRelease(len);
                
                _secKey = SecKeyGenerateSymmetric(parameters, NULL);
            }
        }
    }
    return _secKey;
}
#endif

- (NSData *) encryptData:(NSData *)data {
    
#ifdef AES_USE_OSSL
    NSData *osslResult = [self osslCryptData:data];
    return osslResult;
#else
    
    unsigned char ivec[16];
    memset(ivec, 0, 16);
    NSData *ivData = [NSData dataWithBytes:ivec length:sizeof(ivec)];
    
    SecTransformRef encryptTransform = SecEncryptTransformCreate(self.secKey, NULL);
    if (!encryptTransform) {
        return NULL;
    }
    
    CFErrorRef errorRef = NULL;
    SecTransformSetAttribute(encryptTransform, kSecTransformInputAttributeName, data, NULL);
    SecTransformSetAttribute(encryptTransform, kSecIVKey, ivData, NULL);
    //SecTransformSetAttribute(encryptTransform, kSecModeNoneKey, kCFBooleanTrue, NULL);
    
    NSData *encryptedData = SecTransformExecute(encryptTransform, &errorRef);
    if (errorRef) {
        CFShow(errorRef);
    }

    CFRelease(encryptTransform);

    NSData *result = [NSData dataWithBytes:encryptedData.bytes length:data.length];
    [encryptedData release];
    
    return result;
#endif
    
}

- (void) inplaceEncryptData:(NSMutableData *)data {
#ifdef AES_USE_OSSL
    [self osslInplaceCryptData:data];
#else

#endif
}

- (NSData *) decryptData:(NSData *)data {
    
#ifdef AES_USE_OSSL
    NSData *osslResult = [self osslCryptData:data];
    return osslResult;
#else
    unsigned char ivec[16];
    memset(ivec, 0, 16);
    NSData *ivData = [NSData dataWithBytes:ivec length:sizeof(ivec)];
    
    SecTransformRef decryptTransform = SecDecryptTransformCreate(self.secKey, NULL);
    if (!decryptTransform) {
        return NULL;
    }
    CFErrorRef errorRef = NULL;
    SecTransformSetAttribute(decryptTransform, kSecTransformInputAttributeName, data, &errorRef);
    SecTransformSetAttribute(decryptTransform, kSecIVKey, ivData, NULL);
    //SecTransformSetAttribute(encryptTransform, kSecModeNoneKey, kCFBooleanTrue, NULL);
    
    NSData *decryptedData = SecTransformExecute(decryptTransform, &errorRef);
    if (errorRef) {
        CFShow(errorRef);
    }
    CFRelease(decryptTransform);
    
    return [decryptedData autorelease];
#endif
    
}

- (void) inplaceDecryptData:(NSMutableData *)data {
#ifdef AES_USE_OSSL
    [self osslInplaceCryptData:data];
#else
    
#endif
}

- (void) osslInplaceCryptData:(NSMutableData *)data {

#ifdef AES_USE_OSSL
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    
    int outputLen = (int)data.length + AES_BLOCK_SIZE;
    unsigned char outputBuf[outputLen];
    memset(outputBuf, 0, outputLen);
    
    unsigned char ivec[16];
    memset(ivec, 0, 16);
    
    unsigned char ecount[16];
    memset(ecount, 0, 16);
    
    unsigned int num = 0;
    
    AES_KEY encKey;
    AES_set_encrypt_key(self.keyData.bytes, (int)self.keyData.length * 8, &encKey);
    AES_ctr128_encrypt(data.bytes, data.mutableBytes, data.length, &encKey, ivec, ecount, &num);

#pragma clang diagnostic pop
#endif
    
}

- (NSData *) osslCryptData:(NSData *)data {
    NSData *osslResult = NULL;
    
#ifdef AES_USE_OSSL
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    int outputLen = (int)data.length + AES_BLOCK_SIZE;
    unsigned char outputBuf[outputLen];
    memset(outputBuf, 0, outputLen);
    
    unsigned char ivec[16];
    memset(ivec, 0, 16);
    
    unsigned char ecount[16];
    memset(ecount, 0, 16);
    
    unsigned int num = 0;
    
    AES_KEY encKey;
    AES_set_encrypt_key(self.keyData.bytes, (int)self.keyData.length * 8, &encKey);
    
    for (int i = 0; i < data.length; i += AES_BLOCK_SIZE) {
        AES_ctr128_encrypt(data.bytes + i, outputBuf + i, MIN( AES_BLOCK_SIZE, data.length - i ), &encKey, ivec, ecount, &num);
    }
    
    osslResult = [NSData dataWithBytes:outputBuf length:data.length];
    //[self logMsg:@"SimmetricKey Encription result from OpenSSL:\n%@", osslResult];
    
#pragma clang diagnostic pop
#endif
    
    return osslResult;
}

- (NSData *) randomDataOfLen:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return data;
}

- (id) init {
    self = [super init];
    if (self) {
        _keyLength = AES_KEY_LEN;
        _keyData = [self randomDataOfLen:_keyLength];
        [_keyData retain];
#ifdef AES_USE_OSSL
        
#else
        _secKey = NULL;
        _keyData = NULL;
#endif
    }
    return self;
}

- (id) initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _keyLength = data.length;
        _keyData = data;
        [_keyData retain];
#ifdef AES_USE_OSSL
        
#else
        _secKey = NULL;
#endif
        
    }
    return self;
}

- (void) dealloc {
#ifndef AES_USE_OSSL
    if (_secKey) {
        CFRelease(_secKey);
    }
#endif
    
    [_keyData release];
    
    [super dealloc];
}

@end
