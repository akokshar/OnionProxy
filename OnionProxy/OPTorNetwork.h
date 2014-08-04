//
//  OPTorNetwork.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"
#import "OPCircuit.h"
#import "OPStream.h"

@interface OPTorNetwork : OPObject <OPCircuitDelegate> {

}

+ (OPTorNetwork *) network;

- (OPCircuit *) circuitForDirectoryService;

- (OPStream *) createHTTPStreamForDirectoryServiceWithRequest:(NSURLRequest *)request;

- (void) createCircuit;
- (void) closeCircuit;

- (void) openStream;
- (void) closeStream;

@end
