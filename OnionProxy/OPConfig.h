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

@property (readonly, getter = getMaxJobsCount) NSUInteger maxJobsCount;

@property (readonly, getter = getCacheDir) NSString *cacheDir;
@property (readonly, getter = getServersCount) NSUInteger serversCount;

@property (readonly, getter = getAuthorityCerificateURL) NSString *authorityCerificateURL;
@property (readonly, getter = getAuthorityCerificateFpURL) NSString *authorityCerificateFpURL;
@property (readonly, getter = getNetworkStatusURL) NSString *networkStatusURL;

@property (readonly, getter = getCircuitLength) NSUInteger circuitLength;

+ (OPConfig *) config;

- (NSString *) getNickOfServerAtIndex:(NSUInteger)index;
- (NSString *) getIdentDgstOfServerAtIndex:(NSUInteger)index;
- (NSString *) getFingerprintOfServerAtIndex:(NSUInteger)index;
- (NSString *) getIpAddrOfServerAtIndex:(NSUInteger)index;
- (NSUInteger) getIpPortOfServerAtIndex:(NSUInteger)index;

@end
