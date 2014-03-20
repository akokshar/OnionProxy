//
//  OPPublicKey.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 22/02/14.
//
//

#import "OPRSAPublicKey.h"
#import <Security/Security.h>


@interface OPRSAPublicKey() {

}

@property (readonly) SecKeyRef secKey;
@property (readonly) NSData *digest;

@end

@implementation OPRSAPublicKey

@synthesize secKey = _secKey;

@synthesize digest = _digest;

@synthesize digestHexString;

- (NSString *) getDigestHexString {
    return [self hexStringFromData:_digest];
}

- (id) initWithBase64DerEncodingStr:(NSString *)keyEncoding {
    self = [super init];
    if (self) {
        CFErrorRef error = NULL;
        _secKey = NULL;
        
        NSData *keyData = [self decodeBase64Str:keyEncoding];
        
        if (keyData != NULL) {
            _digest = [self sha1DigestOfData:keyData];
            
            if (_digest != NULL) {
                [_digest retain];
                SecItemImportExportKeyParameters params = {};
                SecExternalFormat externalFormat = kSecFormatUnknown;
                SecExternalItemType itemType = kSecItemTypePublicKey;
                
                CFArrayRef outItems = NULL;
                OSStatus oserr = SecItemImport((CFDataRef)keyData, NULL, &externalFormat, &itemType, CSSM_KEYATTR_EXTRACTABLE, &params, NULL, &outItems);
                if (!oserr && outItems != NULL) {
                    _secKey = (SecKeyRef)CFArrayGetValueAtIndex(outItems, 0);
                    CFRetain(_secKey);
                    CFRelease(outItems);
                    //[self logMsg(@"Key imported");
                }
                else {
                    CFStringRef errorMsg = SecCopyErrorMessageString(oserr, NULL);
                    [self logMsg:@"Loading key with digest: '%@' failed due to '%@'", self.class, errorMsg];
                    CFRelease(errorMsg);
                }
            }
        }

        if (error) {
            CFShow(error);
            CFRelease(error);
        }
        
        if (!_secKey) {
            [self release];
            self = NULL;
        }
        
    }
    return self;
}

- (void) dealloc {
    [_digest release];
    
    [super dealloc];
}

-(BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDataDigest:(NSData *)digestData {
    BOOL result = NO;
    NSData *signatureData = [self decodeBase64Str:signatureStr];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    if (signatureData) {
        
        CSSM_DATA signature;
        signature.Data = (void*)CFDataGetBytePtr((CFDataRef)signatureData);
        signature.Length = CFDataGetLength((CFDataRef)signatureData);
        
        CSSM_DATA digest;
        digest.Data = (void*)CFDataGetBytePtr((CFDataRef)digestData);
        digest.Length = CFDataGetLength((CFDataRef)digestData);
        
        const CSSM_KEY *cssm_key;
        SecKeyGetCSSMKey(_secKey, &cssm_key);
        
        CSSM_CSP_HANDLE csp;
        SecKeyGetCSPHandle(_secKey, &csp);
        
        const CSSM_ACCESS_CREDENTIALS *access_cred;
        SecKeyGetCredentials(_secKey, CSSM_ACL_AUTHORIZATION_SIGN, kSecCredentialTypeDefault, &access_cred);
        
        CSSM_CC_HANDLE cch;
        CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_RSA, access_cred, cssm_key, &cch);
        
        result = (CSSM_OK == CSSM_VerifyData(cch, &digest, 1, CSSM_ALGID_NONE, &signature));

        CSSM_DeleteContext(cch);
    }
    
#pragma clang diagnostic pop
    
    return result;
}

@end
