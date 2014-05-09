//
//  OPSessionKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 26/03/14.
//
//

#define AES_USE_OSSL
//#define AES_USE_CC

#import "OPSimmetricKey.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>

#ifdef AES_USE_OSSL
#import <openssl/aes.h>
#endif

#define AES_KEY_LEN 16

@interface OPSimmetricKey() {
    
}

@property (readonly, getter = getSecKey) SecKeyRef secKey;

- (NSData *) randomDataOfLen:(NSUInteger)length;
- (NSData *) osslEncryptData:(NSData *)data;

@end

@implementation OPSimmetricKey

@synthesize keyLength = _keyLength;

@synthesize keyData = _keyData;

- (NSData *) getKeyData {
    if (self.secKey == NULL) {
        return NULL;
    }
    
    @synchronized(self) {
        if (_keyData == NULL) {
            SecItemImportExportKeyParameters params = {};
            CFDataRef keyDataRef = NULL;
            OSStatus oserr = SecItemExport(self.secKey, kSecFormatRawKey, 0, &params, &keyDataRef);
            if (oserr) {
                fprintf(stderr, "SecItemExport failed (oserr= %d)\n", oserr);
                exit(-1);
            }
    
            _keyData = (NSData *)keyDataRef;
        }
    }
    return _keyData;
}

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

- (NSData *) encryptData:(NSData *)data {
    
#ifdef AES_USE_OSSL
    return [self osslEncryptData:data];
#endif
    
    //CCCrypt(<#CCOperation op#>, <#CCAlgorithm alg#>, <#CCOptions options#>, <#const void *key#>, <#size_t keyLength#>, <#const void *iv#>, <#const void *dataIn#>, <#size_t dataInLength#>, <#void *dataOut#>, <#size_t dataOutAvailable#>, <#size_t *dataOutMoved#>)
    
    SecTransformRef encryptTransform = SecEncryptTransformCreate(self.secKey, NULL);
    if (!encryptTransform) {
        return NULL;
    }
    
    CFErrorRef errorRef = NULL;
    SecTransformSetAttribute(encryptTransform, kSecTransformInputAttributeName, data, NULL);
    //SecTransformSetAttribute(encryptTransform, kSecPaddingKey, kSecPaddingNoneKey, NULL);
    
    NSData *encryptedData = SecTransformExecute(encryptTransform, &errorRef);
    if (errorRef) {
        CFShow(errorRef);
    }

    CFRelease(encryptTransform);

    NSData *result = [NSData dataWithBytes:encryptedData.bytes length:data.length];
    [encryptedData release];
    
    [self logMsg:@"SimmetricKey Encription result from settransform:\n%@", result];

    return result;
}

- (NSData *) osslEncryptData:(NSData *)data {
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
    [self logMsg:@"SimmetricKey Encription result from OpenSSL:\n%@", osslResult];
    
#pragma clang diagnostic pop
#endif
    
    return osslResult;
}

- (NSData *) decryptData:(NSData *)data {
    SecTransformRef decryptTransform = SecDecryptTransformCreate(self.secKey, NULL);
    if (!decryptTransform) {
        return NULL;
    }
    CFErrorRef errorRef = NULL;
    SecTransformSetAttribute(decryptTransform, kSecTransformInputAttributeName, data, &errorRef);
    //SecTransformSetAttribute(decryptTransform, kSecPaddingKey, kSecPaddingNoneKey, NULL);

    NSData *decryptedData = SecTransformExecute(decryptTransform, &errorRef);
    if (errorRef) {
        CFShow(errorRef);
    }
    CFRelease(decryptTransform);
    
    return [decryptedData autorelease];
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
#ifdef AES_USE_OSSL
        _keyData = [self randomDataOfLen:AES_KEY_LEN];
        [_keyData retain];
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
#ifdef AES_USE_OSSL
        
#else
        _keyData = data;
        [_keyData retain];
        _secKey = NULL;
#endif
    }
    return self;
}

- (void) dealloc {
    if (_secKey) {
        CFRelease(_secKey);
    }
    
    [_keyData release];
    
    [super dealloc];
}

@end
