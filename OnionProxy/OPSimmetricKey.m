//
//  OPSessionKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 26/03/14.
//
//

#import "OPSimmetricKey.h"
#import <Security/Security.h>

@interface OPSimmetricKey() {
    
}

@property (readonly) NSUInteger keyLength;
@property (readonly, getter = getSecKey) SecKeyRef secKey;

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
        if (_secKey) {
            return _secKey;
        }

        NSUInteger keyLen = self.keyLength * 8;
        CFNumberRef len = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &keyLen);
        CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeAES);
        CFDictionarySetValue(parameters, kSecAttrKeySizeInBits, len);
        CFRelease(len);
        
        _secKey =  SecKeyGenerateSymmetric(parameters, NULL);
        return _secKey;
    }
}

- (NSData *) encryptData:(NSData *)data {
    SecTransformRef encryptTransform = SecEncryptTransformCreate(self.secKey, NULL);
    if (!encryptTransform) {
        return NULL;
    }
    SecTransformSetAttribute(encryptTransform, kSecTransformInputAttributeName, data, NULL);
    NSData *encryptedData = SecTransformExecute(encryptTransform, NULL);
    CFRelease(encryptTransform);
    
    [self logMsg:@"SimmtricKey encription result = \\n'%@'", encryptedData];
    
    return [encryptedData autorelease];
}

- (NSData *) decryptData:(NSData *)data {
    return NULL;
}

- (id) initWithLength:(NSUInteger)length {
    self = [super init];
    if (self) {
        _secKey = NULL;
        _keyLength = length;
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
