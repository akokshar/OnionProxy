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
#import "OPResourceDownloader.h"
#import "OPRSAPublicKey.h"

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

@property (retain) NSString *ip;

@property (retain, getter = getFingerprint) NSData *fingerprint;
@property (retain) NSData *currentDescriptorDigest;
@property (retain) NSData *freshDescriptorDigest;
@property (assign) BOOL isUpdating;

@property (retain) NSDate *lastUpdated;

//@property (retain) OPRSAPublicKey *signingKey;
@property (retain) OPRSAPublicKey *onionKey;

- (BOOL) processDescriptorDocument:(NSString *)descriptorStr;
- (void) loadDescriptor;

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

@synthesize ip = _ip, orPort = _orPort, dirPort = _dirPort;

@synthesize fingerprint = _fingerprint;
@synthesize currentDescriptorDigest = _currentDescriptorDigest;
@synthesize freshDescriptorDigest = _freshDescriptorDigest;
@synthesize lastUpdated = _lastUpdated;

//@synthesize signingKey;
@synthesize onionKey;

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
        
        NSString *signingKeyStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:2]];
        OPRSAPublicKey *descrSigningKey = [[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:signingKeyStr];
        //self.signingKey = descrSigningKey;
        //[descrSigningKey release];
        
        NSString *signatureStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:3]];
        if (![descrSigningKey verifyBase64SignatureStr:signatureStr forDataDigest:self.freshDescriptorDigest]) {
            //[self logMsg:@"Signature verification failed (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            [descrSigningKey release];
            [pool release];
            return NO;
        }
        [descrSigningKey release];
        
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
        
        //[self logMsg:@"descriptor is OK!!!. So happy :)"];
    }
    else {
        //[self logMsg:@"descriptor pattern missmatch :\n'%@'", rawDescriptorStr];
        [pool release];
        return NO;
    }

    //[pool drain];
    [pool release];
    return YES;
}

- (void) prefetchDescriptor {
    
    if (self.freshDescriptorDigest == NULL) {
        return;
    }

    if (self.isHasLastDescriptor) {
        return;
    }

    @synchronized(self) {
        if (self.isUpdating) {
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
    [OPResourceDownloader downloadResource:self.resourcePath to:self.cacheFilePath timeout:5];
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

- (void) updateWithParams:(NSDictionary *)nodeParams {
    
    if (![self.freshDescriptorDigest isEqualToData:[nodeParams objectForKey:nodeDescriptorDataKey]]) {
        self.freshDescriptorDigest = [nodeParams objectForKey:nodeDescriptorDataKey];
    }
    
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
    
    NSString *ip = [nodeParams objectForKey:nodeIpStrKey];
    if (![self.ip isEqualToString:ip]) {
        self.ip = ip;
    }
    
    NSString *orPort = [nodeParams objectForKey:nodeOrPortStrKey];
    _orPort = [orPort intValue];
    NSString *dirPort = [nodeParams objectForKey:nodeDirPortStrKey];
    _dirPort = [dirPort intValue];
    
    self.lastUpdated = [NSDate date];
}

- (id) initWithParams:(NSDictionary *)nodeParams {
    self = [super init];
    if (self) {
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
    
    self.ip = NULL;
    
    self.fingerprint = NULL;
    self.currentDescriptorDigest = NULL;
    self.freshDescriptorDigest = NULL;
    
    self.lastUpdated = NULL;

    //self.signingKey = NULL;
    self.onionKey = NULL;
    
    dispatch_release(dispatchQueue);

    [super dealloc];
}

@end
