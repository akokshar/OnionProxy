//
//  OPAuthority.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 10/02/14.
//
//

#import "OPAuthority.h"
//#import "OPJobDispatcher.h"
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
        [self logMsg:@"Server %@ ready", authorityServer.nick];
    }
}

- (id) init {
    self = [super init];
    if (self) {
        [self logMsg:@"INIT AUTHORITIES"];
        OPConfig *config = [OPConfig config];
        authorityServers = [[NSMutableDictionary alloc] initWithCapacity:config.serversCount];
        //OPJobDispatcher *jobDispatcher = [[OPJobDispatcher alloc] initWithMaxJobsCount:config.serversCount];
        
        dispatch_queue_t dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
        
        for (int i = 0; i < config.serversCount; i++) {
            dispatch_async(dispatchQueue, ^{
                [self addServer:[NSNumber numberWithInt:i]];
            });
//            [[OPJobDispatcher disparcher] addJobForTarget:self selector:@selector(addServer:) object:[NSNumber numberWithInt:i]];
        }
        
        dispatch_barrier_sync(dispatchQueue, ^{ });
        dispatch_release(dispatchQueue);
        
//        [[OPJobDispatcher disparcher] wait];
        //[jobDispatcher release];
        [self logMsg:@"AUTHORITIES READY"];
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
