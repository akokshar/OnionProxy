//
//  OPTorDirectoryObject.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPTorDirectoryObject.h"
#import "OPConfig.h"
#import "OPTorDirectory.h"

@interface OPTorDirectoryObject() {

}

- (BOOL) downloadFromIp:(NSString *)ip port:(NSUInteger)port resource:(NSString *)resource to:(NSString *)file;
- (BOOL) downloadFromAuthorityResource:(NSString *)resource to:(NSString *)file;

@end

@implementation OPTorDirectoryObject

- (BOOL) downloadFromIp:(NSString *)ip port:(NSUInteger)port resource:(NSString *)resource to:(NSString *)file {
//    NSURL *opdirTestUrl = [NSURL URLWithString:[NSString stringWithFormat:@"opdir://%@", resource]];
//    [self logMsg:@"testUrl '%@'", opdirTestUrl.absoluteString];

    NSURL *opdirUrl = [NSURL URLWithString:[NSString stringWithFormat:@"opdir://%@:%lu%@", ip, (unsigned long)port, resource]];
//    [self logMsg:@"origUrl '%@'", opdirUrl.absoluteString];

    NSURLRequest *request = [NSURLRequest requestWithURL:opdirUrl cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:10];
    NSURLResponse *response;
    NSError *error;
    NSData *resData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (resData) {
        [resData writeToFile:file atomically:YES];
        return YES;
    }
    return NO;
}

- (BOOL) downloadFromAuthorityResource:(NSString *)resource to:(NSString *)file {
    NSUInteger serverIndex = arc4random() % [OPConfig config].serversCount;
    NSString *ip = [[OPConfig config] getIpAddrOfServerAtIndex:serverIndex];
    NSUInteger port = [[OPConfig config] getIpPortOfServerAtIndex:serverIndex];
    return [self downloadFromIp:ip port:port resource:resource to:file];
}

- (BOOL) downloadResource:(NSString *)resource to:(NSString *)file {
    OPTorNode *cacheServer = [[OPTorDirectory directory] getRandomDirectory];

    if (cacheServer) {
        return [self downloadFromIp:cacheServer.ipStr port:cacheServer.dirPort resource:resource to:file];
    }
    else {
        return [self downloadFromAuthorityResource:resource to:file];
    }
}

- (NSData *) downloadResource:(NSString *)resource withCacheFile:(NSString *)file {
    [self downloadResource:resource to:file];
    return [NSData dataWithContentsOfFile:file];
}

@end
