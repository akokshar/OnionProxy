//
//  OPListener.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 30/07/14.
//
//

#import "OPObject.h"

@class OPListener;

@protocol OPListenerDelegate
- (void) listener:(OPListener *)listener connectionWithInputStream:(NSInputStream *)iStream andOutputStream:(NSOutputStream *)oStream;
@end

@interface OPListener : OPObject

- (id) initWithDelegate:(id<OPListenerDelegate>)delegate;

- (BOOL) listenOnIPv4:(NSString *)ip andPort:(uint16)port;

@end
