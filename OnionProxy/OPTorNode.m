//
//  OPTorNode.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 09/02/14.
//
//

#import "OPTorNode.h"
#import "OPConfig.h"
#import "OPSHA1.h"
#import "OPConsensus.h"
#import "OPJobDispatcher.h"
#import "OPRSAPublicKey.h"

#import <arpa/inet.h>

NSString * const nodeFingerprintDataKey = @"FingerprintData";
NSString * const nodeFingerprintStrKey = @"FingerprintStr";
NSString * const nodeDescriptorDataKey = @"DescriptorData";
NSString * const nodeDescriptorStrKey = @"DescriptorStr";
NSString * const nodeIpStrKey = @"IpStr";
NSString * const nodeOrPortStrKey = @"OrPortStr";
NSString * const nodeDirPortStrKey = @"DirPortStr";
NSString * const nodeFlagsStrKey = @"FlagsStr";
NSString * const nodeVersionStrKey = @"VersionStr";
NSString * const nodeBandwidthStrKey = @"BandwidthStr";
NSString * const nodePolicyStrKey = @"PolicyStr";

@interface OPTorNode() {
    dispatch_queue_t dispatchQueue;
    dispatch_semaphore_t descriptorUpdateSemaphore;
    dispatch_semaphore_t descriptorLoadSemaphore;
    NSUInteger updateDelay;
}

@property (readonly, getter = getCacheFilePath) NSString *cacheFilePath;
@property (readonly, getter = getResourcePath) NSString *resourcePath;

@property (atomic) BOOL isExitPolicyAcceptRule;
@property (retain) NSMutableArray *exitRanges;

@property (retain) NSString *ipStr;

@property (retain, getter = getFingerprint) NSData *fingerprint;

@property (retain) NSData *descriptorDigest;
@property (getter=getDescriptorRetainCount, setter=setDescriptorRetainCount:) NSUInteger descriptorRetainCount;

// ***  Descriptor data. to be released by releaseDescriptor
@property (retain) OPRSAPublicKey *identKey;
@property (retain) OPRSAPublicKey *onionKey;
// ***

@property (retain) NSDate *lastUpdated;

- (void) initializeWithParams:(NSDictionary *)nodeParams;

- (BOOL) processDescriptorDocument:(NSString *)descriptorStr;
- (BOOL) loadDescriptor;

@end

@implementation OPTorNode

@synthesize isValid = _isValid;
@synthesize isNamed = _isNamed;
@synthesize isUnnamed = _isUnnamed;
@synthesize isRunning = _isRunning;
@synthesize isStable = _isStable;
@synthesize isExit = _isExit;
@synthesize isBadExit = _isBadExit;
@synthesize isFast = _isFast;
@synthesize isGuard = _isGuard;
@synthesize isAuthority = _isAuthority;
@synthesize isV2Dir = _isV2Dir;
@synthesize isBadDirectory = _isBadDirectory;
@synthesize isHSDir = _isHSDir;

@synthesize ipStr = _ipStr, orPort = _orPort, dirPort = _dirPort;
@synthesize ip = _ip;

@synthesize fingerprint = _fingerprint;
@synthesize descriptorDigest = _descriptorDigest;

@synthesize identKey;
@synthesize onionKey;

@synthesize lastUpdated = _lastUpdated;

@synthesize cacheFilePath;

- (NSString *) getCacheFilePath {
    if (self.fingerprint) {
        return [NSString stringWithFormat:@"%@%@", [OPConfig config].cacheDir, [self hexStringFromData:self.fingerprint]];
    }
    else {
        return NULL;
    }
}

@synthesize resourcePath;

- (NSString *) getResourcePath {
//    if ([[OPConsensus consensus].flavor isEqualToString:@"microdesc"]) {
//        return @"";
//    }
//    else {
        return [NSString stringWithFormat:@"/tor/server/d/%@.z", [self hexStringFromData:self.descriptorDigest]];
//    }
}

@synthesize descriptorRetainCount = _descriptorRetainCount;

- (NSUInteger) getDescriptorRetainCount {
    return _descriptorRetainCount;
}

- (void) setDescriptorRetainCount:(NSUInteger)descriptorRetainCount {
    _descriptorRetainCount = descriptorRetainCount;

    if (_descriptorRetainCount == 0) {
        dispatch_semaphore_wait(descriptorUpdateSemaphore, DISPATCH_TIME_FOREVER);
        self.identKey = NULL;
        self.onionKey = NULL;
        dispatch_semaphore_signal(descriptorUpdateSemaphore);
    }
}

- (BOOL) processDescriptorDocument:(NSString *)rawDescriptorStr {
    if (!rawDescriptorStr || [rawDescriptorStr isEqualTo:@""]) {
        return NO;
    }

    BOOL result = YES;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    NSRegularExpressionOptions optionsRegEx = (NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnixLineSeparators);
    NSString *descriptorPattern = @"(router .*?"
    "signing-key\\n"
    "-----BEGIN RSA PUBLIC KEY-----\\n(.*?)\\n-----END RSA PUBLIC KEY-----"
    ".*?"
    "router-signature\\n)"
    "-----BEGIN SIGNATURE-----\\n(.*?)\\n-----END SIGNATURE-----";
    NSRegularExpression *descriptorRegEx = [NSRegularExpression regularExpressionWithPattern:descriptorPattern options:optionsRegEx error:NULL];
    
    NSArray *descriptorMatch = [descriptorRegEx matchesInString:rawDescriptorStr options:NSMatchingReportProgress range:NSMakeRange(0, [rawDescriptorStr length])];
    if ([descriptorMatch count] == 1) {
        NSTextCheckingResult *match = [descriptorMatch objectAtIndex:0];
        NSString *descriptorStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:1]];
        
        NSData *descriptorDigest = [OPSHA1 digestOfText:descriptorStr];
        
        if (![self.descriptorDigest isEqualToData:descriptorDigest]) {
            [self logMsg:@"Digest missmatch (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            result = NO;
        }

        if (result == YES) {
            NSString *identKeyStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:2]];
            OPRSAPublicKey *descrIdentKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:identKeyStr];
            self.identKey = descrIdentKey;
            [descrIdentKey release];
            
            NSString *signatureStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:3]];
            if (![self.identKey verifyBase64SignatureStr:signatureStr forDataDigest:self.descriptorDigest]) {
                [self logMsg:@"Signature verification failed (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
                result = NO;
            }
        }

        if (result == YES) {
            NSString *onionKeyPattern = @"onion-key\\n-----BEGIN RSA PUBLIC KEY-----\\n(.*?)\\n-----END RSA PUBLIC KEY-----";
            NSRegularExpression *onionKeyRegEx = [NSRegularExpression regularExpressionWithPattern:onionKeyPattern options:optionsRegEx error:NULL];
            NSArray *onionKeyMatch = [onionKeyRegEx matchesInString:descriptorStr options:NSMatchingReportProgress range:NSMakeRange(0, [descriptorStr length])];
            if ([onionKeyMatch count] == 1) {
                match = [onionKeyMatch objectAtIndex:0];
                NSString *onionKeyStr = [descriptorStr substringWithRange:[match rangeAtIndex:1]];
                OPRSAPublicKey *descrOnionKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:onionKeyStr];
                self.onionKey = descrOnionKey;
                [descrOnionKey release];
                
                if (self.onionKey == NULL) {
                    [self logMsg:@"failed to load key from :\n%@", descriptorStr];
                }
            }
            else {
                [self logMsg:@"Descriptor does not contain onion-key (OR fingerprint=%@)", self.fingerprint];
                result = NO;
            }
        }
    }
    else {
        [self logMsg:@"descriptor pattern missmatch :\n'%@'", rawDescriptorStr];
        result = NO;
    }

    if (result == YES) {
        //[self retainDescriptor];
        self.descriptorRetainCount = 1;
    }
    else {
        [self logMsg:@"failed to load descriptor"];
        self.descriptorRetainCount = 0;
    }

    [pool release];
    return result;
}

- (BOOL) loadDescriptor {
    dispatch_semaphore_wait(descriptorLoadSemaphore, DISPATCH_TIME_FOREVER);

    if (self.descriptorRetainCount > 0) {
        dispatch_semaphore_signal(descriptorLoadSemaphore);
        return YES;
    }

    NSData *rawDescriptorData = [self downloadResource:self.resourcePath withCacheFile:self.cacheFilePath];
    NSString *rawDescriptorStr = [[NSString alloc] initWithData:rawDescriptorData encoding:NSUTF8StringEncoding];

    BOOL result = [self processDescriptorDocument:rawDescriptorStr];

    if (!result) {
        [self clearCashedDescriptor];
    }

    [rawDescriptorStr release];

    dispatch_semaphore_signal(descriptorLoadSemaphore);
    
    return result;
}

- (void) prefetchDescriptorAsyncWhenDoneCall:(void (^)(OPTorNode *node))completionHandler {
    dispatch_async(dispatchQueue, ^{
        if ([self loadDescriptor]) {
            completionHandler(self);
        }
        else {
            completionHandler(NULL);
        }
    });
}

- (void) retainDescriptor {
    if (self.descriptorRetainCount == 0) {
        return;
    }
    self.descriptorRetainCount++;
}

- (void) releaseDescriptor {
    if (self.descriptorRetainCount == 0) {
        return;
    }
    self.descriptorRetainCount--;
}

- (void) clearCashedDescriptor {
    if (self.cacheFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.cacheFilePath error:NULL];
    }
}

- (BOOL) canExitToPort:(uint16)port {
    if (!self.isExit) {
        return NO;
    }

    for (NSValue *rangeValue in self.exitRanges) {
        NSRange range = [rangeValue rangeValue];
        return (range.location <= port <= range.length);
    }
    
    return NO;
}

- (BOOL) isEqualTo:(OPTorNode *)node {
    return [self.descriptorDigest isEqualTo:node.descriptorDigest];
}

- (void) initializeWithParams:(NSDictionary *)nodeParams {
    self.fingerprint = [nodeParams objectForKey:nodeFingerprintDataKey];
    self.descriptorDigest = [nodeParams objectForKey:nodeDescriptorDataKey];

    NSString *flagsStr = [nodeParams objectForKey:nodeFlagsStrKey];
    NSArray *flagsArray = [flagsStr componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _isValid = [flagsArray containsObject:@"Valid"];
    _isNamed = [flagsArray containsObject:@"Named"];
    _isUnnamed = [flagsArray containsObject:@"Unamed"];
    _isRunning = [flagsArray containsObject:@"Running"];
    _isStable = [flagsArray containsObject:@"Stable"];
    _isExit = [flagsArray containsObject:@"Exit"];
    _isBadExit = [flagsArray containsObject:@"BadExit"];
    _isFast = [flagsArray containsObject:@"Fast"];
    _isGuard = [flagsArray containsObject:@"Guard"];
    _isAuthority = [flagsArray containsObject:@"Authority"];
    _isV2Dir = [flagsArray containsObject:@"V2Dir"];
    _isBadDirectory = [flagsArray containsObject:@"BadDirectory"];
    _isHSDir = [flagsArray containsObject:@"HSDir"];
    
    NSString *ipStr = [nodeParams objectForKey:nodeIpStrKey];
    if (![self.ipStr isEqualToString:ipStr]) {
        self.ipStr = ipStr;
        inet_pton(AF_INET, [ipStr cStringUsingEncoding:NSUTF8StringEncoding], &_ip);
    }
    
    NSString *orPort = [nodeParams objectForKey:nodeOrPortStrKey];
    _orPort = [orPort intValue];
    NSString *dirPort = [nodeParams objectForKey:nodeDirPortStrKey];
    _dirPort = [dirPort intValue];

    //Example: reject 25,119,135-139,445,563,1214,4661-4666,6346-6429,6699,6881-6999
    NSString *policyConfigutationStr = [[nodeParams objectForKey:nodePolicyStrKey] uppercaseString];
    NSString *exitRangesStr = NULL;
    if ([policyConfigutationStr hasPrefix:@"ACCEPT"]) {
        self.isExitPolicyAcceptRule = YES;
        exitRangesStr = [policyConfigutationStr substringFromIndex:7];
    }
    else if ([policyConfigutationStr hasPrefix:@"REJECT"]) {
        self.isExitPolicyAcceptRule = NO;
        exitRangesStr = [policyConfigutationStr substringFromIndex:7];
    }
    else {
        [self logMsg:@"cant parse exit policy configuration string: '%@'", policyConfigutationStr];
        _isExit = NO;
    }

    if (exitRangesStr) {
        //[self logMsg:@"%@", exitRangesStr];
        NSArray *ranges = [exitRangesStr componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];

        for (NSString *rangeStr in ranges) {
            NSRange range = NSRangeFromString(rangeStr);
            if (range.location != 0 && range.length <= 65535) {
                [self.exitRanges addObject:[NSValue valueWithRange:range]];
            }
        }
        //[self logMsg:@"found %lu ranges", (unsigned long)self.exitRanges.count];
    }

    self.lastUpdated = [NSDate date];
}

- (id) initWithParams:(NSDictionary *)nodeParams {
    self = [super init];
    if (self) {
        dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        descriptorUpdateSemaphore = dispatch_semaphore_create(1);
        descriptorLoadSemaphore = dispatch_semaphore_create(1);

        self.identKey = NULL;
        self.onionKey = NULL;
        
        updateDelay = 0;

        self.fingerprint = NULL;
        self.descriptorDigest = NULL;

        _descriptorRetainCount = 0;

        self.exitRanges  = [NSMutableArray array];
        [self initializeWithParams:nodeParams];
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"dealloc TorNode"];

    self.exitRanges = NULL;

    self.ipStr = NULL;
    
    self.fingerprint = NULL;
    self.descriptorDigest = NULL;

    self.lastUpdated = NULL;

    self.identKey = NULL;
    self.onionKey = NULL;
    
    dispatch_release(dispatchQueue);
    dispatch_release(descriptorUpdateSemaphore);
    dispatch_release(descriptorLoadSemaphore);
    
    [super dealloc];
}

- (oneway void) release {
    [super release];

    if (self.retainCount <= 1) {
        [self releaseDescriptor];
    }
}

@end
