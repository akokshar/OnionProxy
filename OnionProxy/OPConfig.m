//
//  OPConfig.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 16/02/14.
//
//

#import "OPConfig.h"

@interface OPConfig() {
    
}

@property (readonly, getter = getParams) NSDictionary *params;
@property (readonly, getter = getServers) NSArray *servers;

- (NSDictionary *) getServerAtIndex:(NSUInteger)index;

@end

@implementation OPConfig

@synthesize params = _params;

- (NSDictionary *) getParams {
    @synchronized(self) {
        if (!_params) {
            NSString *configPath = [[NSBundle mainBundle] pathForResource:@"OPConfig" ofType:@"plist"];
            _params = [[NSDictionary alloc] initWithContentsOfFile:configPath];
        }
    }
    return _params;
}

@synthesize nodesThreadsCount;

- (NSUInteger) getNodesThreadsCount {
    NSNumber *r = [self.params objectForKey:@"NodesMaxThreadsCount"];
    return [r integerValue];
}

@synthesize consensusThreadsCount;

-(NSUInteger) getConsensusThreadsCount {
    NSNumber *r = [self.params objectForKey:@"ConsensusMaxThreadsCount"];
    return [r integerValue];   
}

@synthesize cacheDir;

- (NSString *) getCacheDir {
    return [self.params objectForKey:@"CacheDir"];
}

@synthesize servers = _servers;

- (NSArray *) getServers {
    return [self.params objectForKey:@"Servers"];
}

@synthesize serversCount;

- (NSUInteger) getServersCount {
    return [self.servers count];
}

@synthesize dirKeyCerificateURL;

- (NSString *) getDirKeyCerificateURL {
    return [self.params objectForKey:@"DirKeyCerificateURL"];
}

@synthesize networkStatusURL;

- (NSString *) getNetworkStatusURL {
    return [self.params objectForKey:@"NetworkStatusURL"];
}

+ (OPConfig *) config {
    static OPConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPConfig alloc] init];
    });
    return instance;
}

- (id) init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (NSDictionary *) getServerAtIndex:(NSUInteger)index {
    return [self.servers objectAtIndex:index];
}

- (NSString *) getNickOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"nick"];
}

- (NSString *) getIdentDgstOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"v3ident"];
}

- (NSString *) getIpAddrOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"ipaddr"];
}

- (NSString *) getIpPortOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"ipport"];
}

@end
