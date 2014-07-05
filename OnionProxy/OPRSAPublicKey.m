//
//  OPPublicKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/02/14.
//
//

#import "OPRSAPublicKey.h"
//#import "OPCSP.h"
#import "OPSHA1.h"
#import <Security/Security.h>
#import <Security/SecEncryptTransform.h>

@interface OPRSAPublicKey() {
    CFArrayRef keyItems;
    SecKeyRef _secKey;
}

@property (readonly, getter = getSecKeyRef) SecKeyRef secKey;

- (NSData *) cssmEncryptData:(NSData *)data;

@end

@implementation OPRSAPublicKey

@synthesize digest = _digest;

@synthesize digestHexString;

- (NSString *) getDigestHexString {
    return [self hexStringFromData:_digest];
}

@synthesize padLength = _padLength;

@synthesize keyLength = _keyLength;

- (NSUInteger) getKeyLength {
    return SecKeyGetBlockSize(self.secKey);
}

@synthesize secKey;

- (SecKeyRef) getSecKeyRef {
    @synchronized(self) {
        if (keyItems) {
            return (SecKeyRef) CFArrayGetValueAtIndex(keyItems, 0);
        }
    }
    return NULL;
}

- (id) initWithBase64DerEncodingStr:(NSString *)keyEncoding {
    self = [super init];
    if (self) {
        _digest = NULL;
        
        NSData *keyData = [self decodeBase64Str:keyEncoding];
        
        if (keyData != NULL) {
            _digest = [OPSHA1 digestOfData:keyData];
            [_digest retain];
            
            _padLength = 42; // OAEP padding len
            
            keyItems = NULL;

            SecItemImportExportKeyParameters params = {};
            SecExternalFormat externalFormat = kSecFormatUnknown;
            SecExternalItemType itemType = kSecItemTypePublicKey;
            
            OSStatus oserr = SecItemImport((CFDataRef)keyData, NULL, &externalFormat, &itemType, CSSM_KEYATTR_EXTRACTABLE, &params, NULL, &keyItems);
            if (oserr || keyItems == NULL) {
                CFStringRef errorMsg = SecCopyErrorMessageString(oserr, NULL);
                [self logMsg:@"Loading key with digest: '%@' failed due to '%@'", self.class, errorMsg];
                CFRelease(errorMsg);
            }
            
//            _secKey = (SecKeyRef) CFArrayGetValueAtIndex(keyItems, 0);
//            CFRetain(_secKey);
//            
//            CFRelease(keyItems);
//            keyItems = NULL;
        }
    }
    return self;
}

- (void) dealloc {
    //[self logMsg:@"dealloc key"];

    /*** !!! Memory leak !!! ***/
    /***  !  Fix it later !  ***/
    if (keyItems) {
        CFRelease(keyItems);
    }
    [_digest release];
    
    [super dealloc];
}

-(BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDataDigest:(NSData *)digestData {
    BOOL result = NO;
    
    if (self.secKey == NULL) {
        return result;
    }
    
    NSData *signatureData = [self decodeBase64Str:signatureStr];

    //
    // SecVerifyTransform fail here - always return false.
    // To play with this later.
    //
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    if (signatureData) {
        
        OSStatus rc;
        
        CSSM_DATA signature;
        signature.Data = (void *)CFDataGetBytePtr((CFDataRef)signatureData);
        signature.Length = CFDataGetLength((CFDataRef)signatureData);
        
        CSSM_DATA digest;
        digest.Data = (void *)CFDataGetBytePtr((CFDataRef)digestData);
        digest.Length = CFDataGetLength((CFDataRef)digestData);
        
        const CSSM_KEY *cssm_key;
        rc = SecKeyGetCSSMKey(self.secKey, &cssm_key);
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"SecKeyGetCSSMKey failed"];
            CFRelease(errorMsg);
        }
        
        CSSM_CSP_HANDLE csp;
        rc = SecKeyGetCSPHandle(self.secKey, &csp);
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"SecKeyGetCSPHandle failed"];
            CFRelease(errorMsg);
        }

        const CSSM_ACCESS_CREDENTIALS *access_cred;
        rc = SecKeyGetCredentials(self.secKey, CSSM_ACL_AUTHORIZATION_SIGN, kSecCredentialTypeDefault, &access_cred);
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"SecKeyGetCredentials failed"];
            CFRelease(errorMsg);
        }
        
        CSSM_CC_HANDLE cch;
        rc = CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_RSA, access_cred, cssm_key, &cch);
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"CSSM_CSP_CreateSignatureContext failed"];
            CFRelease(errorMsg);
        }
        
        result = (CSSM_OK == CSSM_VerifyData(cch, &digest, 1, CSSM_ALGID_NONE, &signature));

        CSSM_DeleteContext(cch);
    }
    
#pragma clang diagnostic pop
    
    return result;
}

- (NSData *) encryptData:(NSData *)data {
    // CSSM does not support OAEP padding? Is always crashing :-(
    //return [self cssmEncryptData:data];

    SecTransformRef encryptTransform = SecEncryptTransformCreate(self.secKey, NULL);
    if (!encryptTransform) {
        return NULL;
    }
    
    SecTransformSetAttribute(encryptTransform, kSecPaddingKey, kSecPaddingOAEPKey, NULL);
//    SecTransformSetAttribute(encryptTransform, kSecOAEPMGF1DigestAlgorithmAttributeName, kSecDigestSHA1, NULL);
    SecTransformSetAttribute(encryptTransform, kSecTransformInputAttributeName, data, NULL);
    NSData *encryptedData = SecTransformExecute(encryptTransform, NULL);
    CFRelease(encryptTransform);
    
    return [encryptedData autorelease];
}

- (NSData *) cssmEncryptData:(NSData *)data {

    NSMutableData *result = NULL;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    CSSM_RETURN crtn;
    
    CSSM_DATA dataStruct;
    dataStruct.Length = CFDataGetLength((CFDataRef)data);
    dataStruct.Data = (void *)CFDataGetBytePtr((CFDataRef)data);
    
    CSSM_CSP_HANDLE csp;
    crtn = SecKeyGetCSPHandle(self.secKey, &csp);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"SecKeyGetCSPHandle failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }

    const CSSM_KEY *cssm_key;
    crtn = SecKeyGetCSSMKey(self.secKey, &cssm_key);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"SecKeyGetCSSMKey failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }
    
    const CSSM_ACCESS_CREDENTIALS *access_cred;
    crtn = SecKeyGetCredentials(self.secKey, CSSM_ACL_AUTHORIZATION_ENCRYPT, kSecCredentialTypeDefault, &access_cred);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"SecKeyGetCredentials failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }

    CSSM_CC_HANDLE cch;
    crtn = CSSM_CSP_CreateAsymmetricContext(csp, CSSM_ALGID_RSA, access_cred, cssm_key, CSSM_PADDING_PKCS1, &cch);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"SecKeyGetCSPHandle failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }
    
    CSSM_PKCS1_OAEP_PARAMS oaepParams;
    oaepParams.HashAlgorithm = CSSM_ALGID_SHA1;
    oaepParams.HashParams.Length = 0;
    oaepParams.HashParams.Data = NULL;
    oaepParams.MGF = CSSM_PKCS_OAEP_MGF1_SHA1;
    oaepParams.MGFParams.Length = 0;
    oaepParams.MGFParams.Data = NULL;
    oaepParams.PSource = CSSM_PKCS_OAEP_PSOURCE_NONE;
    oaepParams.PSourceParams.Length = 0;
    oaepParams.PSourceParams.Data = NULL;

    CSSM_DATA oaepParamsData;
    oaepParamsData.Length = sizeof(oaepParams);
    oaepParamsData.Data = (void *)&oaepParams;
    
    CSSM_CONTEXT_ATTRIBUTE oaepAttributes[2];
    oaepAttributes[1].AttributeType = CSSM_ATTRIBUTE_MODE;
    oaepAttributes[1].AttributeLength = sizeof(uint32_t);
    oaepAttributes[1].Attribute.Uint32 = CSSM_ALGMODE_PKCS1_EME_OAEP;
    oaepAttributes[2].AttributeType = CSSM_ATTRIBUTE_ALG_PARAMS;
    oaepAttributes[2].AttributeLength = sizeof(CSSM_DATA);
    oaepAttributes[2].Attribute.Data = (void *)&oaepParamsData;

    crtn = CSSM_UpdateContextAttributes(cch, 2, oaepAttributes);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"CSSM_UpdateContextAttributes failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }
    
    CSSM_DATA cipherDataStruct;
    memset(&cipherDataStruct, 0, sizeof(cipherDataStruct));

    CSSM_DATA remainedDataStruct;
    memset(&remainedDataStruct, 0, sizeof(remainedDataStruct));
    
    CSSM_SIZE bytesProcessed = 0;
    
    crtn = CSSM_EncryptData(cch, &dataStruct, 1, &cipherDataStruct, 1, &bytesProcessed, &remainedDataStruct);
    if (crtn) {
        CFStringRef errorMsg = SecCopyErrorMessageString(crtn, NULL);
        [self logMsg:@"CSSM_EncryptData failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }
    else {
        result = [NSMutableData dataWithCapacity:cipherDataStruct.Length + remainedDataStruct.Length];
        [result appendBytes:cipherDataStruct.Data length:cipherDataStruct.Length];
        [result appendBytes:remainedDataStruct.Data length:remainedDataStruct.Length];
        [self logMsg:@"RSAPublicKey encryption result from CSSM = \n'%@'", result];
    }
    
    free(cipherDataStruct.Data);
 
#pragma clang diagnostic pop

    return result;
}

@end
