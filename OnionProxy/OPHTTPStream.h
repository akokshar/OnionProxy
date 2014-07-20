//
//  OPHTTPStream.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 07/07/14.
//
//

#import "OPObject.h"
#import "OPCircuit.h"

@class OPHTTPStream;

@protocol OPHTTPStreamDelegate
- (void)stream:(OPHTTPStream *)stream didReceiveResponse:(NSURLResponse *)response;
- (void)stream:(OPHTTPStream *)stream didReceiveData:(NSData *)data;
- (void)streamDidFinishLoading:(OPHTTPStream *)stream;
@end

@interface OPHTTPStream : OPObject <OPCircuitStreamDelegate>

@property (retain) id<OPHTTPStreamDelegate> client;

- (id) initForDirectoryServiceWithCircuit:(OPCircuit *)circuit client:(id<OPHTTPStreamDelegate>)client;
- (id) initWithCircuit:(OPCircuit *)circuit destIp:(NSString *)destIp destPort:(uint16)destPort client:(id<OPHTTPStreamDelegate>)client;

- (void) open;
- (void) close;
- (void) sendData:(NSData *)data;

@end
