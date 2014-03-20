//
//  OPAuthority.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/02/14.
//
//

#import "OPAuthority.h"
#import "OPJobDispatcher.h"
#import "OPAuthorityServer.h"
#import "OPConfig.h"

@interface OPAuthority() {
    NSMutableDictionary *authorityServers;
}

@end

@implementation OPAuthority

@synthesize count;

- (NSUInteger) getCount {
    if (authorityServers) {
        return [authorityServers count];
    }
    return 0;
}

@synthesize randomServer;

- (OPAuthorityServer *) getRandomServer {
    if ([authorityServers count] == 0) {
        return NULL;
    }
    
    NSUInteger randomIndex = arc4random() % [authorityServers count];
    return [authorityServers objectForKey:[authorityServers allKeys][randomIndex]];
}

- (BOOL) verifyBase64SignatureStr:(NSString *)signatureStr ofServerWithIdentDigest:(NSString *)identDigest forDigest:(NSData *)digest {
    OPAuthorityServer *server = [authorityServers objectForKey:identDigest];
    if (server) {
        return [server verifyBase64SignatureStr:signatureStr forDigest:digest];
    }
    return NO;
}

- (void) addServer:(NSNumber *)configIndex {
    OPAuthorityServer *authorityServer = [[OPAuthorityServer alloc] initWithConfigIndex:[configIndex integerValue]];
    if (authorityServer) {
        @synchronized(self) {
            [authorityServers setObject:authorityServer forKey:[[OPConfig config] getIdentDgstOfServerAtIndex:[configIndex integerValue]]];
        }
        [authorityServer release];
    }
    
}

- (id) init {
    self = [super init];
    if (self) {
        OPConfig *config = [OPConfig config];
        authorityServers = [[NSMutableDictionary alloc] initWithCapacity:config.serversCount];
        OPJobDispatcher *jobDispatcher = [[OPJobDispatcher alloc] initWithMaxJobsCount:config.serversCount];
        
        for (int i = 0; i < config.serversCount; i++) {
            [jobDispatcher addJobForTarget:self selector:@selector(addServer:) object:[NSNumber numberWithInt:i]];
        }
        
        [jobDispatcher wait];
        [jobDispatcher release];
    }
    return self;
}

- (void) dealloc {
    [authorityServers release];
    
    [super dealloc];
}

+ (OPAuthority *) authority {
    static OPAuthority *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPAuthority alloc] init];
    });
    return instance;
}

@end
