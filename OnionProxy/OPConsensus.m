//
//  OPConsensus.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 01/03/14.
//

#import "OPConsensus.h"
#import "OPConfig.h"
#import "OPJobDispatcher.h"
#import "OPResourceDownloader.h"
#import "OPAuthority.h"
#import "OPTorNode.h"

NSString * const nodeFingerprintKey = @"Fingerprint";
NSString * const nodeDescriptorKey = @"Descriptor";
NSString * const nodeIpKey = @"Ip";
NSString * const nodeOrPortKey = @"OrPort";
NSString * const nodeDirPortKey = @"DirPort";
NSString * const nodeFlagsKey = @"Flags";

@interface OPConsensus() {
    NSMutableDictionary *nodes;
    OPJobDispatcher *jobDispatcher;
}

@property (readonly, getter = getCacheFilePath) NSString *cacheFilePath;
@property (readonly, getter = getResourcePath) NSString *resourcePath;

@property (retain) NSString *flavor;
@property (retain) NSDate *validAfter;
@property (retain) NSDate *freshUntil;
@property (retain) NSDate *validUntil;
@property (retain) NSDate *lastUpdated;

@property (retain) NSArray *v2DirNodesKeys;
@property (assign) NSUInteger v2DirNodesIndex;

@property (retain) NSArray *exitNodesKeys;
@property (assign) NSUInteger exitNodesIndex;

- (BOOL) processV3ConsensusDocument:(NSString *)consensusStr;
- (void) loadConsensusFromCacheFile;
- (void) updateConsensus;
- (void) scheduleUpdate;

- (void) processNodeWithParams:(NSDictionary *)nodeParams;
- (void) organize;
- (NSArray *) arrayByShufflingArray:(NSArray *)array;

@end

@implementation OPConsensus

@synthesize v2DirNodesKeys, exitNodesKeys;
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

@synthesize randomV2DirNode;

- (OPTorNode *) getRandomV2DirNode {
    OPTorNode *result = NULL;
    
    @synchronized(self) {
        if (self.v2DirNodesKeys) {
            if ([self.v2DirNodesKeys count] > 0) {
                result = [nodes objectForKey:[self.v2DirNodesKeys objectAtIndex:self.v2DirNodesIndex]];
                [result retain];
                
                self.v2DirNodesIndex++;
                if (self.v2DirNodesIndex == [self.v2DirNodesKeys count]) {
                    self.v2DirNodesIndex = 0;
                    self.v2DirNodesKeys = [self arrayByShufflingArray:self.v2DirNodesKeys];
                }
            }
        }
    }
    
    return [result autorelease];
}

@synthesize randomExitNode;

- (OPTorNode *) getRandomExitNode {
    OPTorNode *result = NULL;
    
    @synchronized(self) {
        if (self.exitNodesKeys) {
            if ([self.exitNodesKeys count] > 0) {
                result = [nodes objectForKey:[self.exitNodesKeys objectAtIndex:self.exitNodesIndex]];
                [result retain];
                
                self.exitNodesIndex++;
                if (self.exitNodesIndex == [self.exitNodesKeys count]) {
                    self.exitNodesIndex = 0;
                    self.exitNodesKeys = [self arrayByShufflingArray:self.exitNodesKeys];
                }
                
            }
        }
    }
    
    return [result autorelease];
}

- (NSArray *) arrayByShufflingArray:(NSArray *)array {
    if (array == NULL || [array count] == 0) {
        return array;
    }
    NSMutableArray *tempArray = [NSMutableArray arrayWithArray:array];
    for (NSUInteger i = 0; i < [tempArray count] - 1; i++) {
        NSUInteger j = arc4random() % [tempArray count];
        [tempArray exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    return tempArray;
}

- (void) organize {

    [self.tfCurrentOperation setStringValue:[NSString stringWithFormat:@"Organizing nodes"]];
    [self logMsg:@"Organizing nodes. nodes count: %lu", (unsigned long)[nodes count]];
    
    NSSet *v2DirNodesSet = [nodes keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
        OPTorNode *node = (OPTorNode *)obj;
        if ([self.lastUpdated isLessThan:node.lastUpdated]) {
            return node.isV2Dir;
        }
        return NO;
    }];
    
    @synchronized(self) {
        self.v2DirNodesKeys = [self arrayByShufflingArray:[v2DirNodesSet allObjects]];
        self.v2DirNodesIndex = 0;
        [self.tfDirServersCount setStringValue:[NSString stringWithFormat:@"Directory servers count: %lu", (unsigned long)self.v2DirNodesKeys.count]];
    }
    
    NSSet *exitNodesSet = [nodes keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
        OPTorNode *node = (OPTorNode *)obj;
        if ([self.lastUpdated isLessThan:node.lastUpdated]) {
            return node.isExit;
        }
        return NO;
    }];
    
    @synchronized(self) {
        self.exitNodesKeys = [self arrayByShufflingArray:[exitNodesSet allObjects]];
        self.exitNodesIndex = 0;
        [self.tfExitNodesCount setStringValue:[NSString stringWithFormat:@"Exit nodes count: %lu", (unsigned long)self.exitNodesKeys.count]];
    }
    
    self.lastUpdated = [NSDate date];
    [self scheduleUpdate];
}

- (void) processNodeWithParams:(NSDictionary *)nodeParams {
    OPTorNode *node = NULL;
    
    NSData *fingerprintData = [self decodeBase64Str:[[nodeParams objectForKey:nodeFingerprintKey] stringByAppendingString:@"="]];
    if (fingerprintData == NULL) {
        [self logMsg:@"error while decoding fingerprint '%@'", [nodeParams objectForKey:nodeFingerprintKey]];
        return;
    }
    
    NSData *descrDigestData = [self decodeBase64Str:[[nodeParams objectForKey:nodeDescriptorKey] stringByAppendingString:@"="]];
    
    //@synchronized(self) {
        node = [nodes objectForKey:[nodeParams objectForKey:nodeFingerprintKey]];
    //}
    
    if (node == NULL) {
        node = [[OPTorNode alloc] initWithFingerprint:fingerprintData
                                           descriptor:descrDigestData
                                                   ip:[nodeParams objectForKey:nodeIpKey]
                                               orPort:[nodeParams objectForKey:nodeOrPortKey]
                                              dirPort:[nodeParams objectForKey:nodeDirPortKey]
                                                flags:[nodeParams objectForKey:nodeFlagsKey]];
        @synchronized(self) {
            [nodes setObject:node forKey:[nodeParams objectForKey:nodeFingerprintKey]];
            [self.tfNodesCount setStringValue:[NSString stringWithFormat:@"Total nodes count: %lu", (unsigned long)nodes.count]];
        }
        //[node retriveDescriptor];
        [node release];
    }
    else {
        [node updateWithDescriptor:descrDigestData
                                ip:[nodeParams objectForKey:nodeIpKey]
                            orPort:[nodeParams objectForKey:nodeOrPortKey]
                           dirPort:[nodeParams objectForKey:nodeDirPortKey]
                             flags:[nodeParams objectForKey:nodeFlagsKey]];
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
        NSArray *consensusMatch = [consensusRegEx matchesInString:consensusStr options:NSMatchingReportProgress range:NSMakeRange(0, [consensusStr length])];
        
        if ([consensusMatch count] == 1) {
            self.lastUpdated = [NSDate date];
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
                            sha1 = [self sha1DigestOfText:[consensusStr substringWithRange:[match rangeAtIndex:1]]];
                        }
                        digest = sha1;
                    }
                    else {
                        if (sha256 == NULL) {
                            sha256 = [self sha2DigestOfText:[consensusStr substringWithRange:[match rangeAtIndex:1]] digestLen:256];
                        }
                        digest = sha256;
                    }
                    
                    if ([[OPAuthority authority] verifyBase64SignatureStr:signature ofServerWithIdentDigest:identDigest forDigest:digest]) {
                        validSignaturesCount++;
                    }
                }
                isSignatureValid = (validSignaturesCount == totalSignaturesCount);
                
                [self logMsg:@"Signature verified by %lu authorities", validSignaturesCount];
            }
            
            if (isSignatureValid) {
                self.flavor = [consensusStr substringWithRange:[match rangeAtIndex:3]];
                
                // TODO: parse microdesc router info
                
                NSString *nodePattern = @""
                "r (\\S+) (\\S+) (\\S+) (.*?) (\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}) (\\d+) (\\d+)\\n"
                "(a .*?\\n){0,}"
                "s (.*?)\\n"
                "(v .*?\\n){0,1}"
                "(w .*?\\n){0,1}"
                "(p .*?\\n){0,1}";
                
                NSRegularExpression *nodeRegEx = [NSRegularExpression regularExpressionWithPattern:nodePattern options:optionsRegEx error:NULL];
                if (nodeRegEx) {
                    NSArray *nodesMatch = [nodeRegEx matchesInString:consensusStr options:NSMatchingReportProgress range:[match rangeAtIndex:19]];
                    
                    [self logMsg:@"loading nodes"];
                    for (NSTextCheckingResult *nodeMatch in nodesMatch) {
                        NSDictionary *nodeParams = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:2]], nodeFingerprintKey,
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:3]], nodeDescriptorKey,
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:5]], nodeIpKey,
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:6]], nodeOrPortKey,
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:7]], nodeDirPortKey,
                                                    [consensusStr substringWithRange:[nodeMatch rangeAtIndex:9]], nodeFlagsKey,
                                                    nil];
                        
                        [jobDispatcher addJobForTarget:self selector:@selector(processNodeWithParams:) object:nodeParams];
                        [nodeParams release];
                        //break;
                    }
                }
                
                _validAfter = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:6]]]];
                _freshUntil = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:7]]]];
                _validUntil = [[NSDate alloc] initWithString:[NSString stringWithFormat:@"%@ +0000", [consensusStr substringWithRange:[match rangeAtIndex:8]]]];
                
                [jobDispatcher addBarierTarget:self selector:@selector(organize) object:NULL];
                result = YES;
            }
        }
        else {
            [self logMsg:@"Consensus document does not match template"];
        }
    }
    else {
        [self logMsg:@"internal failure (1) while parsing consensus information"];
    }
    
    [self.tfCurrentOperation setStringValue:[NSString stringWithFormat:@"Processing consensus document done"]];
    [self logMsg:@"Processing consensus document done"];
    
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
}

- (void) updateConsensus {
    [self logMsg:@"Updating consensus"];
    [OPResourceDownloader downloadResource:self.resourcePath to:self.cacheFilePath timeout:5];
    [self loadConsensusFromCacheFile];
}

- (void) scheduleUpdate {
//    [self.tfCurrentOperation setStringValue:[NSString stringWithFormat:@"Scheduling consensus update..."]];
    [self logMsg:@"Scheduling consensus update..."];
    
    if (self.lastUpdated == NULL) {
        [jobDispatcher addJobForTarget:self selector:@selector(updateConsensus) object:NULL];
    }
    else {
        [self logMsg:@"Update in 5 seconds"];

        [jobDispatcher addJobForTarget:self selector:@selector(updateConsensus) object:NULL delayedFor:5];
        return;
        
        if ([self.validUntil isLessThanOrEqualTo:[NSDate date]]) {
            [jobDispatcher addJobForTarget:self selector:@selector(updateConsensus) object:NULL];
            return;
        }
        
        NSDate *updateAfter = [self.freshUntil dateByAddingTimeInterval:ceil([self.validUntil timeIntervalSinceDate:self.freshUntil] * 0.5)];
        NSDate *updateBefore = [self.freshUntil dateByAddingTimeInterval:ceil([self.validUntil timeIntervalSinceDate:self.freshUntil] * 0.75)];
        
        NSTimeInterval updateInterval = [updateBefore timeIntervalSinceDate:updateAfter] * ((float)arc4random() / RAND_MAX);
        NSDate *updateTime = [updateAfter dateByAddingTimeInterval:updateInterval];

        [self.tfCurrentOperation setStringValue:[NSString stringWithFormat:@"Consensus valid till %@. Next update at %@", self.validUntil, updateTime]];
        [self logMsg:@"Consensus valid till %@. Next update at %@", self.validUntil, updateTime];
        [jobDispatcher addJobForTarget:self selector:@selector(updateConsensus) object:NULL delayedFor:[updateTime timeIntervalSinceNow]];
    }
}

//- (id) init {
- (void) consensusInit {
//    self = [super init];
//    if (self) {
        [self logMsg:@"INIT CONSENSUS"];
        nodes = [[NSMutableDictionary alloc] initWithCapacity:5500];
        jobDispatcher = [[OPJobDispatcher alloc] initWithMaxJobsCount:[OPConfig config].consensusThreadsCount];
    
        self.v2DirNodesKeys = NULL;
        self.exitNodesKeys = NULL;
        
        self.validAfter = NULL;
        self.freshUntil = NULL;
        self.validUntil = NULL;
        self.lastUpdated = NULL;
    
        [jobDispatcher addJobForTarget:self selector:@selector(loadConsensusFromCacheFile) object:NULL];
//    }
//    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC CONSENSUS"];
    
    self.validAfter = NULL;
    self.freshUntil = NULL;
    self.validUntil = NULL;
    self.lastUpdated = NULL;
    
    self.v2DirNodesKeys = NULL;
    self.exitNodesKeys = NULL;
    
    [jobDispatcher release];
    [nodes release];
    
    [super dealloc];
}

+ (OPConsensus *) consensus {
    return [[[OPConsensus alloc] init] autorelease];
}

+ (OPConsensus *) instance {
    static OPConsensus *instance = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
        //instance = [[OPConsensus alloc] init];
        [instance consensusInit];
    });
    return instance;
}

+ (id) alloc {
    return [OPConsensus instance];
}

+ (id) allocWithZone:(NSZone *)zone {
    return [OPConsensus instance];
}

- (id) copyWithZone:(NSZone *)zone {
    return self;
}

- (id) retain {
    return self;
}

- (NSUInteger) retainCount {
    return NSUIntegerMax;  //denotes an object that cannot be released
}

- (oneway void) release {
}

- (id) autorelease {
    return self;
}

@end
