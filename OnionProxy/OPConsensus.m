//
//  OPConsensus.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 01/03/14.
//

#import "OPConsensus.h"
#import "OPConfig.h"
#import "OPSHA1.h"
#import "OPSHA256.h"
//#import "OPJobDispatcher.h"
#import "OPAuthority.h"
#import "OPTorNode.h"

@interface OPConsensus() {
    NSMutableDictionary *torNodes;
    dispatch_queue_t dispatchQueue;
//    OPJobDispatcher *jobDispatcher;
}

@property (readonly, getter = getCacheFilePath) NSString *cacheFilePath;
@property (readonly, getter = getResourcePath) NSString *resourcePath;

@property (retain) NSString *flavor;
@property (retain) NSDate *validAfter;
@property (retain) NSDate *freshUntil;
@property (retain) NSDate *validUntil;
@property (retain) NSDate *lastUpdated;

- (BOOL) processV3ConsensusDocument:(NSString *)consensusStr;
- (void) loadConsensusFromCacheFile;
- (void) updateConsensus;
- (void) scheduleUpdate;

- (void) processNodeWithParams:(NSMutableDictionary *)nodeParams;
- (void) organize;

@end

@implementation OPConsensus

@synthesize delegate;

@synthesize validAfter = _validAfter, freshUntil = _freshUntil, validUntil = _validUntil, lastUpdated;
@synthesize  version = _version, flavor = _flavor;

@synthesize cacheFilePath;

- (NSString *) getCacheFilePath {
    return [NSString stringWithFormat:@"%@consensus", [OPConfig config].cacheDir];
}

@synthesize resourcePath;

- (NSString *) getResourcePath {
    return [OPConfig config].networkStatusURL;
}

@synthesize nodes = _nodes;

- (NSDictionary *) getNodes {
    return torNodes;
}

- (void) organize {
    [self logMsg:@"All nodes processed in: %f seconds", [[NSDate date] timeIntervalSinceDate:self.lastUpdated]];
    
    [self.delegate onConsensusUpdatedEvent];

    
    self.lastUpdated = [NSDate date];
    [self scheduleUpdate];
}

- (void) processNodeWithParams:(NSMutableDictionary *)nodeParams {
    OPTorNode *node = NULL;
    
    NSData *fingerprintData = [self decodeBase64Str:[[nodeParams objectForKey:nodeFingerprintStrKey] stringByAppendingString:@"="]];
    if (fingerprintData == NULL) {
        [self logMsg:@"error while decoding fingerprint '%@'", [nodeParams objectForKey:nodeFingerprintStrKey]];
        return;
    }
    [nodeParams setObject:fingerprintData forKey:nodeFingerprintDataKey];
    
    NSData *descrDigestData = [self decodeBase64Str:[[nodeParams objectForKey:nodeDescriptorStrKey] stringByAppendingString:@"="]];
    if (descrDigestData == NULL) {
        [self logMsg:@"error while decoding descriptor digest '%@'", [nodeParams objectForKey:nodeFingerprintStrKey]];
        return;
    }
    [nodeParams setObject:descrDigestData forKey:nodeDescriptorDataKey];

    @synchronized(self) {
        node = [torNodes objectForKey:descrDigestData];
    }
    
    if (node == NULL) {
        node = [[OPTorNode alloc] initWithParams:nodeParams];
        @synchronized(self) {
            [torNodes setObject:node forKey:descrDigestData];
        }

        [self.delegate consensusEvent:OPConsensusEventNodeAdded forNode:node];

        [node release];
    }
}

- (BOOL) processV3ConsensusDocument:(NSString *)consensusStr {
    BOOL result = NO;
    
    if (!consensusStr) {
        return result;
    }
    
    if (![consensusStr hasPrefix:@"network-status-version 3"]) {
        return result;
    }
    
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    NSRegularExpressionOptions optionsRegEx = (NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnixLineSeparators);
    NSString *consensusPattern = @""
    "^(network-status-version (\\d+)\\s?(.*?){0,1}\\n" // $1 signedData $2 version $3 flavor
    "vote-status consensus\\n"
    "(consensus-method (\\d+)\\n){0,1}" // $4 $5 consensus method
    "valid-after (.*?)\\n" // $6
    "fresh-until (.*?)\\n" // $7
    "valid-until (.*?)\\n" // $8
    "voting-delay (\\d+) (\\d+)\\n" // $9 $10
    "(client-versions (.*?)\\n){0,1}" // $11 $12
    "(server-versions (.*?)\\n){0,1}" // $13 $14
    "known-flags (.*?)\\n" // $15
    "(params (.*?)\\n){0,1}" // $16 $17
    "(dir-source .*?\\ncontact .*?\\nvote-digest .*?\\n){0,}" // $18
    "(.*?)" // $19 Nodes
    "(directory-footer\\n"
    "bandwidth-weights (.*?)\\n){0,1}" // $20 $21
    "directory-signature )(.*)"; // $22 Signatures
    NSRegularExpression *consensusRegEx = [NSRegularExpression regularExpressionWithPattern:consensusPattern options:optionsRegEx error:NULL];
    if (consensusRegEx) {
        NSArray *consensusMatch = [consensusRegEx matchesInString:consensusStr options:NSMatchingAnchored range:NSMakeRange(0, [consensusStr length])];
        
        if ([consensusMatch count] == 1) {
            NSTextCheckingResult *match = [consensusMatch objectAtIndex:0];
            
            BOOL isSignatureValid = NO;
            NSString *signaturePattern = @"(sha1 |sha256 ){0,1}([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\\n-----BEGIN SIGNATURE-----\\n(.*?)\\n-----END SIGNATURE-----";
            NSRegularExpression *signatureRegEx = [NSRegularExpression regularExpressionWithPattern:signaturePattern options:optionsRegEx error:NULL];
            if (signatureRegEx) {
                NSInteger validSignaturesCount = 0;
                NSInteger totalSignaturesCount = -1;
                
                NSData *sha256 = NULL;
                NSData *sha1 = NULL;
                NSData *digest = NULL;

                NSArray *signaturesMatch = [signatureRegEx matchesInString:consensusStr options:NSMatchingReportProgress range:[match rangeAtIndex:22]];
                totalSignaturesCount = [signaturesMatch count];

                for (NSTextCheckingResult *signatureMatch in signaturesMatch) {
                    NSString *shaMethod = @"sha1";
                    if ([signatureMatch rangeAtIndex:1].location != NSNotFound) {
                        shaMethod = [consensusStr substringWithRange:[signatureMatch rangeAtIndex:1]];
                    }
                    NSString *identDigest = [consensusStr substringWithRange:[signatureMatch rangeAtIndex:2]];
                    //NSString *signDigest = [consensusStr substringWithRange:[signatureMatch rangeAtIndex:3]];
                    NSString *signature = [consensusStr substringWithRange:[signatureMatch rangeAtIndex:4]];

                    if ([shaMethod hasPrefix:@"sha1"]) {
                        if (sha1 == NULL) {
                            sha1 = [OPSHA1 digestOfText:[consensusStr substringWithRange:[match rangeAtIndex:1]]];
                        }
                        digest = sha1;
                    }
                    else {
                        if (sha256 == NULL) {
                            sha256 = [OPSHA256 digestOfText:[consensusStr substringWithRange:[match rangeAtIndex:1]]];
                        }
                        digest = sha256;
                    }
                    
                    if ([[OPAuthority authority] verifyBase64SignatureStr:signature ofServerWithIdentDigest:identDigest forDigest:digest]) {
                        validSignaturesCount++;
                    }
                }
                isSignatureValid = (validSignaturesCount >= totalSignaturesCount / 3 * 2);
                
                [self logMsg:@"Consensus signatures: %li. Verified: %lu.", totalSignaturesCount, validSignaturesCount];
            }
            
            if (isSignatureValid) {
                self.lastUpdated = [NSDate date];
                
                self.flavor = [consensusStr substringWithRange:[match rangeAtIndex:3]];
                
                // TODO: parse microdesc router info
                
                NSString *nodePattern = @""
                "r (\\S+) (\\S+) (\\S+) (.*?) (\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}) (\\d+) (\\d+)\\n" // $1 $2 $3 $4 $5 $6 $7
                "(a .*?\\n){0,}" // $8
                "s (.*?)\\n" // $9 Flags
                "(v (.*?)\\n){0,1}" // $11 Version
                "(w (.*?)\\n){0,1}" // $13 Bandwidth
                "(p (.*?)\\n){0,1}"; // $15 Policy
                
                NSRegularExpression *nodeRegEx = [NSRegularExpression regularExpressionWithPattern:nodePattern options:optionsRegEx error:NULL];
                if (nodeRegEx) {
                    NSArray *nodesMatch = [nodeRegEx matchesInString:consensusStr options:NSMatchingReportProgress range:[match rangeAtIndex:19]];
                    [self logMsg:@"loading nodes"];
                    for (NSTextCheckingResult *nodeMatch in nodesMatch) {
                        NSMutableDictionary *nodeParams = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:2]], nodeFingerprintStrKey,
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:3]], nodeDescriptorStrKey,
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:5]], nodeIpStrKey,
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:6]], nodeOrPortStrKey,
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:7]], nodeDirPortStrKey,
                                                           [consensusStr substringWithRange:[nodeMatch rangeAtIndex:9]], nodeFlagsStrKey,
                                                           nil];
                        if ([nodeMatch rangeAtIndex:10].location != NSNotFound) {
                            [nodeParams setObject:[consensusStr substringWithRange:[nodeMatch rangeAtIndex:11]] forKey:nodeVersionStrKey];
                        }
                        if ([nodeMatch rangeAtIndex:12].location != NSNotFound) {
                            [nodeParams setObject:[consensusStr substringWithRange:[nodeMatch rangeAtIndex:13]] forKey:nodeBandwidthStrKey];
                        }
                        if ([nodeMatch rangeAtIndex:14].location != NSNotFound) {
                            [nodeParams setObject:[consensusStr substringWithRange:[nodeMatch rangeAtIndex:15]] forKey:nodePolicyStrKey];
                        }
             
                        dispatch_async(dispatchQueue, ^{
                            [self processNodeWithParams:nodeParams];
                        });
                        
//                        [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(processNodeWithParams:) object:nodeParams];
                        
                        [nodeParams release];
                        //break;
                    }
                }
                
                _validAfter = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:6]]]];
                _freshUntil = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:7]]]];
                _validUntil = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:8]]]];
                
                dispatch_barrier_async(dispatchQueue, ^{
                    [self organize];
                });
                
//                [[OPJobDispatcher disparcher] addBarierTarget:self selector:@selector(organize) object:NULL];
                result = YES;
            }
            else {
                [self logMsg:@"Consensus signature verification failed"];
            }
        }
        else {
            [self logMsg:@"Consensus document does not match template"];
        }
    }
    else {
        [self logMsg:@"internal failure (1) while parsing consensus information"];
    }
    
    [self logMsg:@"Processing consensus document done"];
    
    [pool release];
    
    return result;
}

- (void) loadConsensusFromCacheFile {
    NSString *rawConsensusStr = NULL;
    NSData *rawConsensusData = [NSData dataWithContentsOfFile:self.cacheFilePath];
    
    if (rawConsensusData) {
        rawConsensusStr = [[[NSString alloc] initWithData:rawConsensusData encoding:NSUTF8StringEncoding] autorelease];
    }
    
    if ([self processV3ConsensusDocument:rawConsensusStr]) {
        [self logMsg:@"Consensus loaded"];
    }
    else {
        [self logMsg:@"Failed to load consensus"];
        [self scheduleUpdate];
    }
    [self logMsg:@"loadConsensusFromCacheFile DONE"];
}

- (void) updateConsensus {
    [self logMsg:@"Updating consensus"];

//    if ([OPResourceDownloader downloadResource:self.resourcePath to:self.cacheFilePath timeout:5]) {
    if ([self downloadResource:self.resourcePath to:self.cacheFilePath]) {
        [self loadConsensusFromCacheFile];
    }
    else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatchQueue, ^{
            [self updateConsensus];
        });
//        [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateConsensus) object:NULL delayedFor:10];
    }
}

- (void) scheduleUpdate {
//    [self.tfCurrentOperation setStringValue:[NSString stringWithFormat:@"Scheduling consensus update..."]];
    [self logMsg:@"Scheduling consensus update..."];
    
    if (self.lastUpdated == NULL) {
        [self logMsg:@"No consensus. Update now"];
        dispatch_async(dispatchQueue, ^{
            [self updateConsensus];
        });
//        [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateConsensus) object:NULL];
    }
    else {
//        [self logMsg:@"Update in 5 seconds"];
//        [jobDispatcher addJobForTarget:self selector:@selector(updateConsensus) delayedFor:5];
//        return;
        
        if ([self.validUntil isLessThanOrEqualTo:[NSDate date]]) {
            [self logMsg:@"Consensus too old. Update now"];
            dispatch_async(dispatchQueue, ^{
                [self updateConsensus];
            });
//            [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateConsensus) object:NULL];
            return;
        }
        
        NSDate *updateAfter = [self.freshUntil dateByAddingTimeInterval:ceil([self.validUntil timeIntervalSinceDate:self.freshUntil] * 3/4)];
        NSDate *updateBefore = [self.freshUntil dateByAddingTimeInterval:ceil([self.validUntil timeIntervalSinceDate:self.freshUntil] * 7/8)];
        
        NSTimeInterval updateInterval = [updateBefore timeIntervalSinceDate:updateAfter] * ((float)arc4random() / RAND_MAX);
        NSDate *updateTime = [updateAfter dateByAddingTimeInterval:updateInterval];

        [self logMsg:@"Consensus valid till %@. Next update at %@", self.validUntil, updateTime];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([updateTime timeIntervalSinceNow] * NSEC_PER_SEC)), dispatchQueue, ^{
            [self updateConsensus];
        });
//        [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(updateConsensus) object:NULL delayedFor:[updateTime timeIntervalSinceNow]];
    }
}

- (id) init {
    self = [super init];
    if (self) {
        [self logMsg:@"INIT CONSENSUS"];
        torNodes = [[NSMutableDictionary alloc] initWithCapacity:5500];
        //    jobDispatcher = [[OPJobDispatcher alloc] initWithMaxJobsCount:[OPConfig config].consensusJobsCount];
        dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        
        self.validAfter = NULL;
        self.freshUntil = NULL;
        self.validUntil = NULL;
        self.lastUpdated = NULL;
        
        dispatch_async(dispatchQueue, ^{
            [self loadConsensusFromCacheFile];
        });
        
        //    [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(loadConsensusFromCacheFile) object:NULL];
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC CONSENSUS"];
    
    self.validAfter = NULL;
    self.freshUntil = NULL;
    self.validUntil = NULL;
    self.lastUpdated = NULL;
    
    dispatch_release(dispatchQueue);
//    [jobDispatcher release];
    [torNodes release];
    
    [super dealloc];
}

@end
