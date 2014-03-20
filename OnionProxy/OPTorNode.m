//
//  OPTorNode.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 09/02/14.
//
//

#import "OPTorNode.h"
#import "OPConfig.h"
#import "OPJobDispatcher.h"
#import "OPConsensus.h"
#import "OPResourceDownloader.h"
#import "OPRSAPublicKey.h"

@interface OPTorNode() {
    OPJobDispatcher *jobDispatcher;
}

@property (readonly, getter = getCacheFilePath) NSString *cacheFilePath;
@property (readonly, getter = getResourcePath) NSString *resourcePath;

@property (retain) NSString *ip;
@property (retain) NSString *orPort;
@property (retain) NSString *dirPort;

@property (retain) NSData *fingerprint;
@property (retain) NSData *currentDescriptorDigest;
@property (retain) NSData *freshDescriptorDigest;
@property (atomic) BOOL isUpdating;

@property (retain) NSDate *lastUpdated;

@property (retain) OPRSAPublicKey *signingKey;
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

@synthesize cacheFilePath;

- (NSString *) getCacheFilePath {
    return [NSString stringWithFormat:@"%@%@", [OPConfig config].cacheDir, [self hexStringFromData:self.fingerprint]];
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
    
    NSRegularExpressionOptions optionsRegEx = (NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnixLineSeparators);
    NSString *descriptorPattern = @"(router .*?"
    "signing-key\\n"
    "-----BEGIN RSA PUBLIC KEY-----(.*?)-----END RSA PUBLIC KEY-----"
    ".*?"
    "router-signature\\n)"
    "-----BEGIN SIGNATURE-----(.*?)-----END SIGNATURE-----";
    NSRegularExpression *descriptorRegEx = [NSRegularExpression regularExpressionWithPattern:descriptorPattern options:optionsRegEx error:NULL];
    
    NSArray *descriptorMatch = [descriptorRegEx matchesInString:rawDescriptorStr options:NSMatchingReportProgress range:NSMakeRange(0, [rawDescriptorStr length])];
    
    if ([descriptorMatch count] == 1) {
        NSTextCheckingResult *match = [descriptorMatch objectAtIndex:0];
        NSString *descriptorStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:1]];

        if (![self.freshDescriptorDigest isEqualToData:[self sha1DigestOfData:[descriptorStr dataUsingEncoding:NSUTF8StringEncoding]]]) {
            [self logMsg:@"Digest missmatch (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            return NO;
        }
        
        NSString *signingKeyStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:2]];
        self.signingKey = [[[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:signingKeyStr] autorelease];
        
        NSString *signatureStr = [rawDescriptorStr substringWithRange:[match rangeAtIndex:3]];
        if (![self.signingKey verifyBase64SignatureStr:signatureStr forDataDigest:self.freshDescriptorDigest]) {
            [self logMsg:@"Signature verification failed (OR fingerprint=%@). Rejecting router descriptor.", self.fingerprint];
            return NO;
        }
        
        NSString *onionKeyPattern = @"onion-key\\n-----BEGIN RSA PUBLIC KEY-----(.*?)-----END RSA PUBLIC KEY-----";
        NSRegularExpression *onionKeyRegEx = [NSRegularExpression regularExpressionWithPattern:onionKeyPattern options:optionsRegEx error:NULL];
        NSArray *onionKeyMatch = [onionKeyRegEx matchesInString:descriptorStr options:NSMatchingReportProgress range:NSMakeRange(0, [descriptorStr length])];
        if (![onionKeyMatch count] == 1) {
            [self logMsg:@"Descriptor does not contain onion-key (OR fingerprint=%@)", self.fingerprint];
            return NO;
        }
        match = [onionKeyMatch objectAtIndex:0];
        NSString *onionKeyStr = [descriptorStr substringWithRange:[match rangeAtIndex:1]];
        self.onionKey = [[[OPRSAPublicKey alloc] initWithBase64DerEncodingStr:onionKeyStr] autorelease];
        
        //[self logMsg:@"descriptor is OK!!!. So happy :)"];
    }

    return YES;
}

- (void) retriveDescriptor {
    
    if (self.freshDescriptorDigest == NULL) {
        return;
    }
    
    if (self.isHasLastDescriptor) {
        return;
    }

    @synchronized(self) {
        if (!self.isUpdating) {
            self.isUpdating = YES;
        
            if (self.currentDescriptorDigest == NULL) {
                // if this is a very first load attempt try to bypass downloading - check cached information first
                [jobDispatcher addJobForTarget:self selector:@selector(loadDescriptor) object:NULL];
            }
            else {
                [jobDispatcher addJobForTarget:self selector:@selector(updateDescriptor) object:NULL];
            }
        }
    }
}

- (void) updateDescriptor {
    [OPResourceDownloader downloadResource:self.resourcePath to:self.cacheFilePath timeout:5];
    [self loadDescriptor];
}

- (void) loadDescriptor {
    NSData *rawDescriptorData = [NSData dataWithContentsOfFile:self.cacheFilePath];
    NSString *rawDescriptorStr = NULL;
    
    if (rawDescriptorData) {
        rawDescriptorStr = [[NSString alloc] initWithData:rawDescriptorData encoding:NSUTF8StringEncoding];
    }
    
    if ([self processDescriptorDocument:rawDescriptorStr]) {
        self.currentDescriptorDigest = self.freshDescriptorDigest;
        self.isUpdating = NO;
    }
    else {
//        NSTimeInterval delay = 1.0; // TODO: Implement update delays
//        [[OPThreadDispatcher nodesBundle] addJobForTarget:self selector:@selector(updateDescriptor) object:NULL delayedFor:delay];
        [jobDispatcher addJobForTarget:self selector:@selector(updateDescriptor) object:NULL];
    }
    
    [rawDescriptorStr release];
}

- (void) cleanCachedInfo {
    if (self.cacheFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.cacheFilePath error:NULL];
    }
}

- (void) updateWithDescriptor:(NSData *)digest ip:(NSString *)ip orPort:(NSString *)orPort dirPort:(NSString *)dirPort flags:(NSString *)flags {
    
    if (![self.freshDescriptorDigest isEqualToData:digest]) {
        self.freshDescriptorDigest = digest;
    }
    
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

    if (![self.ip isEqualToString:ip]) {
        self.ip = ip;
    }
    
    if (![self.orPort isEqualToString:orPort]) {
        self.orPort = orPort;
    }
    
    if (![self.dirPort isEqualToString:dirPort]) {
        self.dirPort = dirPort;
    }
    
    self.lastUpdated = [NSDate date];
}

- (id) initWithFingerprint:(NSData *)fingerprint descriptor:(NSData *)digest ip:(NSString *)ip orPort:(NSString *)orPort dirPort:(NSString *)dirPort flags:(NSString *)flags {
    self = [super init];
    if (self) {
        static OPJobDispatcher *jobDispatcherInstance = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            jobDispatcherInstance = [[OPJobDispatcher alloc] initWithMaxJobsCount:[OPConfig config].nodesThreadsCount];
        });
        jobDispatcher = jobDispatcherInstance;

        self.fingerprint = fingerprint;
        self.freshDescriptorDigest = NULL;
        self.currentDescriptorDigest = NULL;

        self.isUpdating = NO;
        
        [self updateWithDescriptor:digest ip:ip orPort:orPort dirPort:dirPort flags:flags];
     }
    return self;
}

- (void) dealloc {
    self.ip = NULL;
    self.orPort = NULL;
    self.dirPort = NULL;
    
    self.fingerprint = NULL;
    self.currentDescriptorDigest = NULL;
    self.freshDescriptorDigest = NULL;
    
    self.lastUpdated = NULL;

    [super dealloc];
}

@end
