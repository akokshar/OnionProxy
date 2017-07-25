//
//  OPHTTPStream.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 07/07/14.
//
//

#import "OPObject.h"
#import "OPCircuit.h"

@class OPStream;

@protocol OPStreamDelegate
- (void) streamDidConnect:(OPStream *)stream;
- (void) streamDidDisconnect:(OPStream *)stream;
- (void) stream:(OPStream *)stream didReceiveData:(NSData *)data;
- (void) stream:(OPStream *)connection didFailWithError:(NSError *)error;
@end

@interface OPStream : OPObject <OPCircuitStreamDelegate>

- (void) open;
- (void) close;
- (void) sendData:(NSData *)data;

+ (OPStream *) directoryStreamForClient:(id<OPStreamDelegate>)client;
+ (OPStream *) streamToHost:(NSString *)host forClient:(id<OPStreamDelegate>)client;

@end
