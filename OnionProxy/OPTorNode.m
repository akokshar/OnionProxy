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
    NSUInteger updateDelay;
}

@property (readonly, getter = getCacheFilePath) NSString *cacheFilePath;
@property (readonly, getter = getResourcePath) NSString *resourcePath;

@property (retain) NSString *ipStr;

@property (retain, getter = getFingerprint) NSData *fingerprint;
@property (retain) NSData *freshDescriptorDigest;

// ***  Descriptor data. to be released by releaseDescriptor
@property (atomic, retain) NSData *currentDescriptorDigest;
@property (retain) OPRSAPublicKey *identKey;
@property (retain) OPRSAPublicKey *onionKey;
// ***

@property (assign) BOOL isUpdating;
@property (retain) NSDate *lastUpdated;

- (BOOL) processDescriptorDocument:(NSString *)descriptorStr;
- (void) loadDescriptor;
- (void) releaseDescriptor;

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
@synthesize freshDescriptorDigest = _freshDescriptorDigest;
@synthesize currentDescriptorDigest = _currentDescriptorDigest;
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
        return [NSString stringWithFormat:@"/tor/server/d/%@.z", [self hexStringFromData:self.freshDescriptorDigest]];
//    }
}

@synthesize isHasLastDescriptor;

- (BOOL) getIsHasLastDescriptor {
    return (self.currentDescriptorDigest == self.freshDescriptorDigest);
}

- (BOOL) processDescriptorDocument:(NSString *)rawDescriptorStr {
    if (!rawDescriptorStr) {
        return NO;
    }
    
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
        
        if (![self.freshDescriptorDigest isEqualToData:descriptorDigest]) {
            //[self logMsg:@"Digest missmatch (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            [pool release];
            return NO;
        }
        
        NSString *identKeyStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:2]];
        OPRSAPublicKey *descrIdentKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:identKeyStr];
        self.identKey = descrIdentKey;
        [descrIdentKey release];
        
        NSString *signatureStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:3]];
        if (![self.identKey verifyBase64SignatureStr:signatureStr forDataDigest:self.freshDescriptorDigest]) {
            //[self logMsg:@"Signature verification failed (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            [pool release];
            return NO;
        }
        
        NSString *onionKeyPattern = @"onion-key\\n-----BEGIN RSA PUBLIC KEY-----\\n(.*?)\\n-----END RSA PUBLIC KEY-----";
        NSRegularExpression *onionKeyRegEx = [NSRegularExpression regularExpressionWithPattern:onionKeyPattern options:optionsRegEx error:NULL];
        NSArray *onionKeyMatch = [onionKeyRegEx matchesInString:descriptorStr options:NSMatchingReportProgress range:NSMakeRange(0, [descriptorStr length])];
        if (![onionKeyMatch count] == 1) {
            [self logMsg:@"Descriptor does not contain onion-key (OR fingerprint=%@)", self.fingerprint];
            [pool release];
            return NO;
        }
        match = [onionKeyMatch objectAtIndex:0];
        NSString *onionKeyStr = [descriptorStr substringWithRange:[match rangeAtIndex:1]];
        OPRSAPublicKey *descrOnionKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:onionKeyStr];
        self.onionKey = descrOnionKey;
        [descrOnionKey release];
        
        if (self.onionKey == NULL) {
            [self logMsg:@"failed to load key from :\n%@", descriptorStr];
        }
        
        [self.delegate torNode:self event:OPTorNodeDescriptorReadyEvent];
        
        //[self logMsg:@"descriptor is OK!!!. So happy :)"];
    }
    else {
        //[self logMsg:@"descriptor pattern missmatch :\n'%@'", rawDescriptorStr];
        [pool release];
        return NO;
    }
    
//    [self logMsg:@"%@",rawDescriptorStr];
//    [self logMsg:@">>>%@", self.identKey.digest];

    //[pool drain];
    [pool release];
    return YES;
}

- (void) prefetchDescriptor {
    
    if (self.freshDescriptorDigest == NULL) {
        [self.delegate torNode:self event:OPTorNodeDescriptorUpdateFailedEvent];
        return;
    }

    @synchronized(self) {
        if (self.isHasLastDescriptor) {
            [self.delegate torNode:self event:OPTorNodeDescriptorReadyEvent];
            return;
        }

        if (self.isUpdating) {
            [self.delegate torNode:self event:OPTorNodeDescriptorUpdateInProgressEvent];
            return;
        }

        self.isUpdating = YES;
        updateDelay = 0;
        
        if (self.currentDescriptorDigest == NULL) {
            // if this is a very first load attempt try to bypass downloading - check cached information first
//            dispatch_async(dispatchQueue, ^{
//                [self loadDescriptor];
//            });
            [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(loadDescriptor) object:NULL];
        }
        else {
            // this branch is, probably, not needed at all
//            dispatch_async(dispatchQueue, ^{
//                [self updateDescriptor];
//            });
            [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateDescriptor) object:NULL];
        }

    }
}

- (void) updateDescriptor {
//    [OPResourceDownloader downloadResource:self.resourcePath to:self.cacheFilePath timeout:5];
    [self downloadResource:self.resourcePath to:self.cacheFilePath];
    [self loadDescriptor];
}

- (void) loadDescriptor {
    NSData *rawDescriptorData = [[NSData alloc] initWithContentsOfFile:self.cacheFilePath];
    NSString *rawDescriptorStr = [[NSString alloc] initWithData:rawDescriptorData encoding:NSUTF8StringEncoding];
    
    if ([self processDescriptorDocument:rawDescriptorStr]) {
        self.currentDescriptorDigest = self.freshDescriptorDigest;
        self.isUpdating = NO;
    }
    else {
        NSUInteger delay = updateDelay;
        if (updateDelay < 60) {
            updateDelay += arc4random() % 16;
        }
        else {
            updateDelay -= arc4random() % 16;
        }
        
        //
        // TODO: this can leave cache files lost and not cleared ever.
        // to implement Invalidation of delayed update or to check if this node is marked as dead.
        
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatchQueue, ^{
//            [self updateDescriptor];
//        });
        [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateDescriptor) object:NULL delayedFor:delay];
    }
    
    [rawDescriptorStr release];
    [rawDescriptorData release];
}

- (void) cleanCachedInfo {
    if (self.cacheFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.cacheFilePath error:NULL];
    }
}

- (void) releaseDescriptor {
    @synchronized(self) {
        self.currentDescriptorDigest = NULL;
        self.identKey = NULL;
        self.onionKey = NULL;
    }
}

- (void) updateWithParams:(NSDictionary *)nodeParams {
    
//    if (self.freshDescriptorDigest == NULL || ![self.freshDescriptorDigest isEqualToData:[nodeParams objectForKey:nodeDescriptorDataKey]]) {
    self.freshDescriptorDigest = [nodeParams objectForKey:nodeDescriptorDataKey];

    NSString *flags = [nodeParams objectForKey:nodeFlagsStrKey];
    NSArray *array = [flags componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _isValid = [array containsObject:@"Valid"];
    _isNamed = [array containsObject:@"Named"];
    _isUnnamed = [array containsObject:@"Unamed"];
    _isRunning = [array containsObject:@"Running"];
    _isStable = [array containsObject:@"Stable"];
    _isExit = [array containsObject:@"Exit"];
    _isBadExit = [array containsObject:@"BadExit"];
    _isFast = [array containsObject:@"Fast"];
    _isGuard = [array containsObject:@"Guard"];
    _isAuthority = [array containsObject:@"Authority"];
    _isV2Dir = [array containsObject:@"V2Dir"];
    _isBadDirectory = [array containsObject:@"BadDirectory"];
    _isHSDir = [array containsObject:@"HSDir"];
    
    NSString *ipStr = [nodeParams objectForKey:nodeIpStrKey];
    if (![self.ipStr isEqualToString:ipStr]) {
        self.ipStr = ipStr;
        inet_pton(AF_INET, [ipStr cStringUsingEncoding:NSUTF8StringEncoding], &_ip);
    }
    
    NSString *orPort = [nodeParams objectForKey:nodeOrPortStrKey];
    _orPort = [orPort intValue];
    NSString *dirPort = [nodeParams objectForKey:nodeDirPortStrKey];
    _dirPort = [dirPort intValue];
//    }
    
    self.lastUpdated = [NSDate date];
}

- (id) initWithParams:(NSDictionary *)nodeParams {
    self = [super init];
    if (self) {
        self.delegate = NULL;
        
        dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        
        //self.signingKey = NULL;
        self.onionKey = NULL;
        
        updateDelay = 0;
        
        self.fingerprint = [nodeParams objectForKey:nodeFingerprintDataKey];
        self.freshDescriptorDigest = NULL;
        self.currentDescriptorDigest = NULL;
        
        self.isUpdating = NO;
        
        [self updateWithParams:nodeParams];
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"dealloc TorNode"];
    
    self.ipStr = NULL;
    
    self.fingerprint = NULL;
    self.currentDescriptorDigest = NULL;
    self.freshDescriptorDigest = NULL;
    
    self.lastUpdated = NULL;

    //self.signingKey = NULL;
    self.onionKey = NULL;
    
    dispatch_release(dispatchQueue);

    self.delegate = NULL;
    
    [super dealloc];
}

- (oneway void) release {
    [super release];

    if (self.retainCount == 1) {
        [self releaseDescriptor];
    }
}

@end
