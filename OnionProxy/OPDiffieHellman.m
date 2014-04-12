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

//30 81 95
//06 09 2A 86 48 86 F7 0D 01 03 01
//30 81 87
//02 81 81
//00 FF FF FF FF FF FF FF FF C9 0F DA A2 21 68 C2 34 C4 C6 62 8B 80 DC 1C D1 29 02 4E 08
//8A 67 CC 74 02 0B BE A6 3B 13 9B 22 51 4A 08 79 8E 34 04 DD EF 95 19 B3 CD 3A 43 1B
//30 2B 0A 6D F2 5F 14 37 4F E1 35 6D 6D 51 C2 45 E4 85 B5 76 62 5E 7E C6 F4 4C 42 E9
//A6 37 ED 6B 0B FF 5C B6 F4 06 B7 ED EE 38 6B FB 5A 89 9F A5 AE 9F 24 11 7C 4B 1F E6
//49 28 66 51 EC E6 53 81 FF FF FF FF FF FF FF FF
//02 01 02
//02 01 7F

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
                        "\x04\x00";

@interface OPDiffieHellman() {
    CSSM_KEY private;
    CSSM_KEY public;
}

@end

@implementation OPDiffieHellman

@synthesize EData = _EData;

- (NSData *) getEData {
    @synchronized(self) {
        if (_EData) {
            return _EData;
        }
        
        CSSM_DATA dhKeyAgreement;
        dhKeyAgreement.Data = (void *)dhKeyAgreementBytes;
        dhKeyAgreement.Length = sizeof(dhKeyAgreementBytes);
        
        CSSM_RETURN rc;
        CSSM_CC_HANDLE ccHandle;
        rc = CSSM_CSP_CreateKeyGenContext([OPCSP instance].handle, CSSM_ALGID_DH, 1024, NULL, NULL, NULL, NULL, &dhKeyAgreement, &ccHandle);
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"CSSM_CSP_CreateKeyGenContext failed '%@'", errorMsg];
            CFRelease(errorMsg);
        }
        
        rc = CSSM_GenerateKeyPair(ccHandle,
                                    CSSM_KEYUSE_DERIVE,		// only legal use of a Diffie-Hellman key
                                    CSSM_KEYATTR_RETURN_DATA | CSSM_KEYATTR_EXTRACTABLE,
                                    NULL,
                                    &public,                // public
                                    CSSM_KEYUSE_DERIVE,
                                    CSSM_KEYATTR_RETURN_REF,
                                    NULL,				// same labels
                                    NULL,				// CredAndAclEntry
                                    &private);                //private
        if (rc) {
            CFStringRef errorMsg = SecCopyErrorMessageString(rc, NULL);
            [self logMsg:@"CSSM_GenerateKeyPair failed '%@'", errorMsg];
            CFRelease(errorMsg);
        }

        CSSM_DeleteContext(ccHandle);
        
        return [NSData dataWithBytes:public.KeyData.Data length:public.KeyData.Length];
     }
}

- (id) init {
    self = [super init];
    if (self) {
        _EData = NULL;
        memset(&private, 0, sizeof(CSSM_KEY));
        memset(&public, 0, sizeof(CSSM_KEY));
     }
    return self;
}

- (void) dealloc {
    CSSM_FreeKey([OPCSP instance].handle, NULL, &private, CSSM_FALSE);
    CSSM_FreeKey([OPCSP instance].handle, NULL, &public, CSSM_FALSE);
    
    [super dealloc];
}

@end

#pragma clang diagnostic pop
