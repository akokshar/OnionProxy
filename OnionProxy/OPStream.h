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

@protocol OPHTTPStreamDelegate
- (void) stream:(OPStream *)stream didReceiveResponse:(NSURLResponse *)response;
- (void) stream:(OPStream *)stream didReceiveData:(NSData *)data;
- (void) streamDidFinishLoading:(OPStream *)stream;
- (void) stream:(OPStream *)connection didFailWithError:(NSError *)error;
@end

@interface OPStream : OPObject <OPCircuitStreamDelegate>

- (id) initForDirectoryServiceWithCircuit:(OPCircuit *)circuit client:(id<OPHTTPStreamDelegate>)client request:(NSURLRequest *)request;
- (id) initWithCircuit:(OPCircuit *)circuit destIp:(NSString *)destIp destPort:(uint16)destPort client:(id<OPHTTPStreamDelegate>)client;

- (void) open;
- (void) close;
- (void) sendData:(NSData *)data;

+ (OPStream *) streamForClient:(id<OPHTTPStreamDelegate>)client withDirectoryResourceRequest:(NSURLRequest *)request;
+ (OPStream *) directoryStreamForClient:(id<OPHTTPStreamDelegate>)client;


@end
