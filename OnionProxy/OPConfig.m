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

@synthesize maxJobsCount;

-(NSUInteger) getMaxJobsCount {
    NSNumber *count = [self.params objectForKey:@"MaxJobsCount"];
    if (count) {
        return [count integerValue];
    }
    return 64;
}

@synthesize cacheDir;

- (NSString *) getCacheDir {
    @synchronized(self) {
        return [self.params objectForKey:@"CacheDir"];
    }
}

@synthesize servers = _servers;

- (NSArray *) getServers {
    return [self.params objectForKey:@"Servers"];
}

@synthesize serversCount;

- (NSUInteger) getServersCount {
    return [self.servers count];
}

@synthesize authorityCerificateURL;

- (NSString *) getAuthorityCerificateURL {
    return [self.params objectForKey:@"AuthorityCerificateURL"];
}

@synthesize authorityCerificateFpURL;

- (NSString *) getAuthorityCerificateFpURL {
    return [self.params objectForKey:@"AuthorityCerificateFpURL"];
}

@synthesize networkStatusURL;

- (NSString *) getNetworkStatusURL {
    return [self.params objectForKey:@"NetworkStatusURL"];
}

@synthesize circuitLength;

- (NSUInteger) getCircuitLength {
    NSNumber *length = [self.params objectForKey:@"CircuitLength"];
    if (length) {
        return [length integerValue];
    }
    return 8;
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

- (NSString *) getFingerprintOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"fingerprint"];
}

- (NSString *) getIpAddrOfServerAtIndex:(NSUInteger)index {
    return [[self getServerAtIndex:index] objectForKey:@"ipaddr"];
}

- (NSUInteger) getIpPortOfServerAtIndex:(NSUInteger)index {
    return [[[self getServerAtIndex:index] objectForKey:@"ipport"] intValue];
}

@end
