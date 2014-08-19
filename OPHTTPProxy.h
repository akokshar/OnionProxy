//
//  OPHTTPProxy.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 04/08/14.
//
//

#import "OPObject.h"

@interface OPHTTPProxy : OPObject 

+ (void) serveConnectionWithInputStream:(NSInputStream *)iStream andOutputStream:(NSOutputStream *)oStream;

@end
