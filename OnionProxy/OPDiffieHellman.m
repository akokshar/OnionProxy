//
//  OPDiffieHellman.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 29/03/14.
//
//

#define DH_USE_OSSL
#undef DH_USE_CSSM

#import "OPDiffieHellman.h"
#import "OPCSP.h"

#ifdef DH_USE_OSSL
#import <openssl/bn.h>
#import <openssl/dh.h>
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

char const * dhPrimeStr = ""
          "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E08"
          "8A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B"
          "302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9"
          "A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE6"
          "49286651ECE65381FFFFFFFFFFFFFFFF";

char const * dhGeneratorStr = "02";

int const dhPrivateKeySize = 1024;
int const dhPrivateKeyLen = 128;
int const dhPublicKeySize = 1024;
int const dhPublicKeyLen = 128;

uint8_t const dhKeyAgreementBytes[] = ""
            "\x30\x81\x95"          // Sequence
                "\x06\x09\x2A\x86\x48\x86\xF7\x0D\x01\x03\x01"      // OID DhKeyAgreement
                "\x30\x81\x87"      // Sequence
                    "\x02\x81\x81"  // Integer Prime
                        "\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xC9\x0F\xDA\xA2\x21\x68\xC2\x34\xC4\xC6\x62\x8B\x80\xDC\x1C\xD1\x29\x02\x4E\x08"
                        "\x8A\x67\xCC\x74\x02\x0B\xBE\xA6\x3B\x13\x9B\x22\x51\x4A\x08\x79\x8E\x34\x04\xDD\xEF\x95\x19\xB3\xCD\x3A\x43\x1B"
                        "\x30\x2B\x0A\x6D\xF2\x5F\x14\x37\x4F\xE1\x35\x6D\x6D\x51\xC2\x45\xE4\x85\xB5\x76\x62\x5E\x7E\xC6\xF4\x4C\x42\xE9"
                        "\xA6\x37\xED\x6B\x0B\xFF\x5C\xB6\xF4\x06\xB7\xED\xEE\x38\x6B\xFB\x5A\x89\x9F\xA5\xAE\x9F\x24\x11\x7C\x4B\x1F\xE6"
                        "\x49\x28\x66\x51\xEC\xE6\x53\x81\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"
                    "\x02\x01"          // Integer generator
                        "\x02";
//                    "\x02\x02"          // Integer privateValueLength
//                        "\x04\x00";


@interface OPDiffieHellman() {

    CSSM_KEY aPrivate;
    CSSM_KEY aPublic;

    NSData *requestData;
    
    DH *dh;
    
}

- (NSData *) osslGenerateRequest;
- (NSData *) cssmGenerateRequest;

- (NSData *) osslDeriveSimmetricKeyDataWithResonse:(NSData *)response;
- (NSData *) cssmDeriveSimmetricKeyDataWithResonse:(NSData *)response;

@end

@implementation OPDiffieHellman

@synthesize request;

- (NSData *) getRequest {
    @synchronized(self) {
        if (requestData == NULL) {
            
#ifdef DH_USE_CSSM
            requestData = [self cssmGenerateRequest];
#endif
            
#ifdef DH_USE_OSSL
            requestData = [self osslGenerateRequest];
#endif

        }
    }
    return requestData;
}

- (NSData *) osslGenerateRequest {
    DH_generate_key(dh);
    
    size_t requestLen = BN_num_bytes(dh->pub_key);

    uint8_t requestBytes[requestLen];
    memset(requestBytes, 0, requestLen);

    BN_bn2bin(dh->pub_key, requestBytes + (128 - requestLen));

    requestData = [[NSData alloc] initWithBytes:requestBytes length:requestLen];
    
    return requestData;
}

- (NSData *) cssmGenerateRequest {
    CSSM_RETURN rc;

    /*/////
    //
    // Test format of key generation parameters
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

    rc = CSSM_CSP_CreateKeyGenContext([OPCSP instance].handle, CSSM_ALGID_DH, 1024, NULL, NULL, NULL, NULL, &dhKeyAgreement, &ccHandle);
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

    //[self logMsg:@"CSSM PRIVATE KEY:\n%@", [NSData dataWithBytes:aPrivate.KeyData.Data length:aPrivate.KeyData.Length]];

    requestData = [[NSData alloc] initWithBytes:aPublic.KeyData.Data length:aPublic.KeyData.Length];

    CSSM_DeleteContext(ccHandle);
    
    return requestData;
}

- (NSData *) deriveSimmetricKeyDataWithResonse:(NSData *)response {
    
#ifdef DH_USE_CSSM
    return [self cssmDeriveSimmetricKeyDataWithResonse:response];
#endif
    
#ifdef DH_USE_OSSL
    return [self osslDeriveSimmetricKeyDataWithResonse:response];
#endif
    
}

- (NSData *) osslDeriveSimmetricKeyDataWithResonse:(NSData *)response {
    BIGNUM *rsp = BN_new();
    NSMutableData *sharedKey = [NSMutableData dataWithLength:dhPrivateKeyLen];
    
    BN_bin2bn((unsigned char *)response.bytes, (int)response.length, rsp);
    DH_compute_key((unsigned char*)sharedKey.mutableBytes, rsp, dh);
    
    BN_free(rsp);
    
    return sharedKey;
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

    [self logMsg:@"CSSM KEY:\n%@", [NSData dataWithBytes:aPublic.KeyData.Data length:aPublic.KeyData.Length]];

    return simmetricKeyData;
}

- (id) init {
    self = [super init];
    if (self) {
        requestData = NULL;

#ifdef DH_USE_CSSM
        
        memset(&aPrivate, 0, sizeof(CSSM_KEY));
        memset(&aPublic, 0, sizeof(CSSM_KEY));
        
#endif
        
#ifdef DH_USE_OSSL
        
        static BIGNUM *dhPrime;
        static BIGNUM *dhGenerator;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dhPrime = BN_new();
            BN_hex2bn(&dhPrime, dhPrimeStr);
            
            dhGenerator = BN_new();
            BN_hex2bn(&dhGenerator, dhGeneratorStr);
        });
        
        dh = DH_new();
        dh->p = BN_dup(dhPrime);
        dh->g = BN_dup(dhGenerator);
        dh->length = dhPrivateKeySize;
        
#endif
        
     }
    return self;
}

- (void) dealloc {
    
#ifdef DH_USE_CSSM
    CSSM_FreeKey([OPCSP instance].handle, NULL, &aPrivate, CSSM_FALSE);
    CSSM_FreeKey([OPCSP instance].handle, NULL, &aPublic, CSSM_FALSE);
#endif
    
#ifdef DH_USE_OSSL
    DH_free(dh);
#endif
    
    [requestData release];
    
    [super dealloc];
}

@end

#pragma clang diagnostic pop
