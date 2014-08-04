//
//  OPDiffieHellman.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 29/03/14.
//
//

#import "OPDiffieHellman.h"
#import "OPCSP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int const dhPublicKeySize = 1024;
int const dhPublicKeyLen = 128;

uint8_t const dhKeyAgreementBytes[] = ""
            "\x30\x81\x99"          // Sequence
                "\x06\x09\x2A\x86\x48\x86\xF7\x0D\x01\x03\x01"      // OID DhKeyAgreement
                "\x30\x81\x8B"      // Sequence
                    "\x02\x81\x81"  // Integer Prime
                        "\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xC9\x0F\xDA\xA2\x21\x68\xC2\x34\xC4\xC6\x62\x8B\x80\xDC\x1C\xD1\x29\x02\x4E\x08"
                        "\x8A\x67\xCC\x74\x02\x0B\xBE\xA6\x3B\x13\x9B\x22\x51\x4A\x08\x79\x8E\x34\x04\xDD\xEF\x95\x19\xB3\xCD\x3A\x43\x1B"
                        "\x30\x2B\x0A\x6D\xF2\x5F\x14\x37\x4F\xE1\x35\x6D\x6D\x51\xC2\x45\xE4\x85\xB5\x76\x62\x5E\x7E\xC6\xF4\x4C\x42\xE9"
                        "\xA6\x37\xED\x6B\x0B\xFF\x5C\xB6\xF4\x06\xB7\xED\xEE\x38\x6B\xFB\x5A\x89\x9F\xA5\xAE\x9F\x24\x11\x7C\x4B\x1F\xE6"
                        "\x49\x28\x66\x51\xEC\xE6\x53\x81\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"
                    "\x02\x01"          // Integer generator
                        "\x02"
                    "\x02\x02"          // Integer privateValueLength
                        "\x04\x00";     //1024

@interface OPDiffieHellman() {
    CSSM_KEY aPrivate;
    CSSM_KEY aPublic;
    NSData *requestData;
}

- (NSData *) cssmGenerateRequest;
- (NSData *) cssmDeriveSimmetricKeyDataWithResonse:(NSData *)response;

@end

@implementation OPDiffieHellman

@synthesize request;

- (NSData *) getRequest {
    @synchronized(self) {
        if (requestData == NULL) {
            requestData = [self cssmGenerateRequest];
        }
    }
    return requestData;
}

- (NSData *) cssmGenerateRequest {
    CSSM_RETURN rc;

    /*/////
    //
    // Test format of key generation parameters. To be the same as in dhKeyAgreementBytes.
    //
    CSSM_CC_HANDLE ccH;
    rc = CSSM_CSP_CreateKeyGenContext([OPCSP instance].handle, CSSM_ALGID_DH, 1024, NULL, NULL, NULL, NULL, NULL, &ccH);
    if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_CSP_CreateKeyGenContext failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }

    CSSM_DATA par;
     
    // this call take a long time
    rc = CSSM_GenerateAlgorithmParams(ccH, 1024, &par);
    if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_GenerateAlgorithmParams failed '%@'", errorMsg];
        CFRelease(errorMsg);
    }

    [self logMsg:@"PRAMS GENERATED:\n%@", [NSData dataWithBytes:par.Data length:par.Length]];

    CSSM_DeleteContext(ccH);
    /////*/

    CSSM_CC_HANDLE ccHandle;
    CSSM_DATA dhKeyAgreement;
    dhKeyAgreement.Data = (void *)dhKeyAgreementBytes;
    dhKeyAgreement.Length = sizeof(dhKeyAgreementBytes) - 1;

    rc = CSSM_CSP_CreateKeyGenContext([OPCSP instance].handle, CSSM_ALGID_DH, dhPublicKeySize, NULL, NULL, NULL, NULL, &dhKeyAgreement, &ccHandle);
    if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_CSP_CreateKeyGenContext failed '%@'", errorMsg];
        CFRelease(errorMsg);
        return NULL;
    }

    rc = CSSM_GenerateKeyPair(ccHandle,
                              CSSM_KEYUSE_DERIVE,
                              CSSM_KEYATTR_RETURN_DATA | CSSM_KEYATTR_EXTRACTABLE,
                              NULL,
                              &aPublic,
                              CSSM_KEYUSE_DERIVE,
                              CSSM_KEYATTR_RETURN_DATA | CSSM_KEYATTR_EXTRACTABLE,
                              NULL,
                              NULL,
                              &aPrivate);
    if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_GenerateKeyPair failed '%@'", errorMsg];
        CFRelease(errorMsg);
        return NULL;
    }

    requestData = [[NSData alloc] initWithBytes:aPublic.KeyData.Data length:aPublic.KeyData.Length];

    CSSM_DeleteContext(ccHandle);
    
    return requestData;
}

- (NSData *) deriveSimmetricKeyDataWithResonse:(NSData *)response {
    return [self cssmDeriveSimmetricKeyDataWithResonse:response];
}

- (NSData *) cssmDeriveSimmetricKeyDataWithResonse:(NSData *)response {

    CSSM_CC_HANDLE ccHandle;
    CSSM_ACCESS_CREDENTIALS creds;
    CSSM_RETURN rc;
    
    memset(&creds, 0, sizeof(CSSM_ACCESS_CREDENTIALS));
    
    rc = CSSM_CSP_CreateDeriveKeyContext([OPCSP instance].handle,
                                           CSSM_ALGID_DH,
                                           CSSM_ALGID_DH, // not important
                                           1024,
                                           &creds,
                                           &aPrivate,	// BaseKey
                                           0,			// IterationCount
                                           0,			// Salt
                                           0,			// Seed
                                           &ccHandle);
	if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_CSP_CreateDeriveKeyContext failed '%@'", errorMsg];
        CFRelease(errorMsg);
		return NULL;
	}

    CSSM_DATA bPublic = { response.length, (uint8 *)response.bytes };
    CSSM_DATA labelData = {13, (uint8 *)"SimmetricKey"};
    CSSM_KEY derivedKey;
    memset(&derivedKey, 0, sizeof(CSSM_KEY));
   
    rc = CSSM_DeriveKey(ccHandle,
                        &bPublic,
                        CSSM_KEYUSE_ANY,
                        CSSM_KEYATTR_RETURN_DATA | CSSM_KEYATTR_EXTRACTABLE,
                        &labelData,
                        NULL,
                        &derivedKey);
    
    CSSM_DeleteContext(ccHandle);
	
    if (rc) {
        CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
        [self logMsg:@"CSSM_DeriveKey failed '%@'", errorMsg];
        CFRelease(errorMsg);
		return NULL;
	}
    
    NSData *simmetricKeyData = [NSData dataWithBytes:derivedKey.KeyData.Data length:derivedKey.KeyData.Length];
    
    CSSM_FreeKey([OPCSP instance].handle,
                 NULL,
                 &derivedKey,
                 CSSM_FALSE);

    return simmetricKeyData;
}

- (id) init {
    self = [super init];
    if (self) {
        requestData = NULL;
        memset(&aPrivate, 0, sizeof(CSSM_KEY));
        memset(&aPublic, 0, sizeof(CSSM_KEY));
     }
    return self;
}

- (void) dealloc {
    CSSM_FreeKey([OPCSP instance].handle, NULL, &aPrivate, CSSM_FALSE);
    CSSM_FreeKey([OPCSP instance].handle, NULL, &aPublic, CSSM_FALSE);
    [requestData release];
    
    [super dealloc];
}

@end

#pragma clang diagnostic pop
