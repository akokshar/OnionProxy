//
//  OPConfig.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 16/02/14.
//
//

#import <Foundation/Foundation.h>

#include "OPObject.h"

@interface OPConfig : OPObject {
    
}

@property (readonly, getter = getNodesThreadsCount) NSUInteger nodesThreadsCount;
@property (readonly, getter = getConsensusThreadsCount) NSUInteger consensusThreadsCount;

@property (readonly, getter = getCacheDir) NSString *cacheDir;
@property (readonly, getter = getServersCount) NSUInteger serversCount;

@property (readonly, getter = getDirKeyCerificateURL) NSString *dirKeyCerificateURL;
@property (readonly, getter = getNetworkStatusURL) NSString *networkStatusURL;

+ (OPConfig *) config;

- (NSString *) getNickOfServerAtIndex:(NSUInteger)index;
- (NSString *) getIdentDgstOfServerAtIndex:(NSUInteger)index;
- (NSString *) getIpAddrOfServerAtIndex:(NSUInteger)index;
- (NSString *) getIpPortOfServerAtIndex:(NSUInteger)index;

@end
