//
//  OPTorNetwork.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"
#import "OPCircuit.h"
#import "OPHTTPStream.h"

@interface OPTorNetwork : OPObject <OPCircuitDelegate> {

}

+ (OPTorNetwork *) network;

- (OPHTTPStream *) createHTTPStreamForDirectoryService;

- (void) createCircuit;
- (void) closeCircuit;

- (void) openStream;
- (void) closeStream;

@end
