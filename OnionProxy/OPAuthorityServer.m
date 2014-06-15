//
//  OPAuthorityServer.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 15/02/14.
//
//

#import "OPAuthorityServer.h"
#import "OPConfig.h"
#import "OPSHA1.h"
#import "OPRSAPublicKey.h"

#import <zlib.h>

#import <Security/SecTransform.h>

@interface OPAuthorityServer() {
    NSUInteger configIndex;
}

@property (nonatomic, setter = setIdentPublicKey:) OPRSAPublicKey *identPublicKey;
@property (nonatomic, setter = setSignPublicKey:) OPRSAPublicKey *signPublicKey;

- (BOOL) loadKeysWithForcedDownload:(BOOL)download;
- (BOOL) processV3DirKeyCertificateDocument:(NSString *)keysStr;

@end

@implementation OPAuthorityServer

@synthesize ip;

- (NSString *) getIp {
    return [[OPConfig config] getIpAddrOfServerAtIndex:configIndex];
}

@synthesize dirPort;

- (NSUInteger) getDirPort {
    return [[OPConfig config] getIpPortOfServerAtIndex:configIndex];
}

@synthesize nick;

- (NSString *) getNick {
    return [[OPConfig config] getNickOfServerAtIndex:configIndex];
}

@synthesize identPublicKey = _identPublicKey;

- (void) setIdentPublicKey:(OPRSAPublicKey *)identPublicKey {
    @synchronized(self) {
        if (_identPublicKey) {
            [_identPublicKey release];
        }
        _identPublicKey = identPublicKey;
        [_identPublicKey retain];
    }
}

@synthesize signPublicKey = _signPublicKey;

- (void) setSignPublicKey:(OPRSAPublicKey *)signPublicKey {
    @synchronized(self) {
        if (_signPublicKey) {
            [_signPublicKey release];
        }
        _signPublicKey = signPublicKey;
        [_signPublicKey retain];
    }
}

- (BOOL) loadKeysWithForcedDownload:(BOOL)download {
    NSData *rawKeysData = NULL;
    OPConfig *config = [OPConfig config];
    NSString *cacheFilePath = [NSString stringWithFormat:@"%@%@", config.cacheDir, [config getIdentDgstOfServerAtIndex:configIndex]];
    
    if (download == NO) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:cacheFilePath]) {
            rawKeysData = [NSData dataWithContentsOfFile:cacheFilePath];
        }
    }
    
    if (!rawKeysData) {
        NSString *resourceUrlStr = [NSString stringWithFormat:@"%@%@.z", [config getAuthorityCerificateFpURL], [config getIdentDgstOfServerAtIndex:configIndex]];
        [self downloadResource:resourceUrlStr to:cacheFilePath];
//        [OPResourceDownloader downloadResource:resourceUrlStr to:cacheFilePath timeout:3];
        rawKeysData = [NSData dataWithContentsOfFile:cacheFilePath];
    }
    
    if (!rawKeysData) {
        [self logMsg:@"Cant load keys for server '%@'", [config getNickOfServerAtIndex:configIndex]];
        return NO;
    }
    
    BOOL result = NO;
    NSString *keysStr = [[NSString alloc] initWithData:rawKeysData encoding:NSUTF8StringEncoding];
    
    if ([keysStr hasPrefix:@"dir-key-certificate-version 3"]) {
        result = [self processV3DirKeyCertificateDocument:keysStr];
    }
    else {
        [self logMsg:@"Unsupported dir-key-certificate document version"];
    }
    
    [keysStr release];
    
    return result;
}

- (BOOL) processV3DirKeyCertificateDocument:(NSString *)keysStr {
    if (!keysStr) {
        return NO;
    }
    
    BOOL result = NO;
    OPConfig *config = [OPConfig config];
    
    NSRegularExpressionOptions optionsRegEx = (NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnixLineSeparators);
    // Specification does not say that order of fields is strict
    // but current format is as this. Go the easy way for now...
    NSString *keyCertPattern = @"^(dir-key-certificate-version (\\d+)\\n"
    "(dir-address (\\d+)\\n){0,1}"
    "fingerprint ([0-9A-Fa-f]+)\\n"
    "dir-key-published (\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\n"
    "dir-key-expires (\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\n"
    "dir-identity-key\\n-----BEGIN RSA PUBLIC KEY-----\\n(.*?)\\n-----END RSA PUBLIC KEY-----\\n"
    "dir-signing-key\n-----BEGIN RSA PUBLIC KEY-----\\n(.*?)\\n-----END RSA PUBLIC KEY-----\n"
    "(dir-key-crosscert\\n-----BEGIN ID SIGNATURE-----\\n(.*?)\\n-----END ID SIGNATURE-----\\n){0,1}"
    "dir-key-certification\\n)-----BEGIN SIGNATURE-----\\n(.*?)\\n-----END SIGNATURE-----$";
    NSRegularExpression *keyCertRegEx = [NSRegularExpression regularExpressionWithPattern:keyCertPattern options:optionsRegEx error:NULL];
    
    if (keyCertRegEx) {
        NSArray *keyCertMatch = [keyCertRegEx matchesInString:keysStr options:NSMatchingReportProgress range:NSMakeRange(0, [keysStr length])];
        
        if ([keyCertMatch count] == 1) {
            NSTextCheckingResult *match = [keyCertMatch objectAtIndex:0];
        
            NSMutableDictionary *keysInfoTmp = [NSMutableDictionary dictionaryWithCapacity:13];
            
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:2]] forKey:@"dir-key-certificate-version"];
            if ([match rangeAtIndex:3].location != NSNotFound) {
                [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:4]] forKey:@"dir-address"];
            }
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:5]] forKey:@"dir-identity-key-digest"];
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:6]] forKey:@"dir-key-published"];
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:7]] forKey:@"dir-key-expires"];
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:8]] forKey:@"dir-identity-key"];
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:9]] forKey:@"dir-signing-key"];
            if ([match rangeAtIndex:10].location != NSNotFound) {
                [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:11]] forKey:@"dir-key-crosscert"];
            }
            [keysInfoTmp setObject:[keysStr substringWithRange:[match rangeAtIndex:12]] forKey:@"dir-key-certification"];
            
            OPRSAPublicKey *identKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:[keysInfoTmp objectForKey:@"dir-identity-key"]];
            self.identPublicKey = identKey;
            [identKey release];
            if (self.identPublicKey && [self.identPublicKey.digestHexString isCaseInsensitiveLike:[config getIdentDgstOfServerAtIndex:configIndex]]) {
                OPRSAPublicKey *signKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:[keysInfoTmp objectForKey:@"dir-signing-key"]];
                self.signPublicKey = signKey;
                [signKey release];
                
                if ([keysInfoTmp objectForKey:@"dir-key-crosscert"]) {
                    // TODO: Verivy crosscert
                }
                
                NSData *signedTextDigest = [OPSHA1 digestOfText:[keysStr substringWithRange:[match rangeAtIndex:1]]];
                BOOL isVerified = [self.identPublicKey verifyBase64SignatureStr:[keysInfoTmp objectForKey:@"dir-key-certification"] forDataDigest:signedTextDigest];
                if (isVerified) {
                    //[self logMsg:@"Keys signature verified for '%@'", [config getNickOfServerAtIndex:configIndex]];
                    result = YES;
                }
                else {
                    [self logMsg:@"Keys signature verification failed for '%@'", [config getNickOfServerAtIndex:configIndex]];
                }
            }
            else {
                [self logMsg:@"Key digest missmatch for '%@'", [config getNickOfServerAtIndex:configIndex]];
            }
        }
        else {
            [self logMsg:@"DirJeyCertificate document does not match template '%@'", [config getNickOfServerAtIndex:configIndex]];
        }
    }
    else {
        [self logMsg:@"internal failure (1] while parsing keys informationfor '%@'", [config getNickOfServerAtIndex:configIndex]];
    }

    return result;
}

- (BOOL) verifyBase64SignatureStr:(NSString *)signatureStr forDigest:(NSData *)digest {
    if (self.signPublicKey == NULL) {
        return NO;
    }
    return [self.signPublicKey verifyBase64SignatureStr:signatureStr forDataDigest:digest];
}

-(id) initWithConfigIndex:(NSUInteger)index {
    self = [super init];
    if (self) {
        _identPublicKey = NULL;
        _signPublicKey = NULL;
        configIndex = index;
        
        if ([self loadKeysWithForcedDownload:NO] == NO) {
            [self logMsg:@"Error while initialising authority '%@'", [[OPConfig config] getNickOfServerAtIndex:configIndex]];
            [self release];
            self = NULL;
        }
        
        // TODO: check expiration dates
    }
    return self;
}

- (void) dealloc {
    self.identPublicKey = NULL;
    self.signPublicKey = NULL;
    
    [super dealloc];
}

@end
