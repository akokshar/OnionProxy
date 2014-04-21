//
//  OPDiffieHellman.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 29/03/14.
//
//

#import "OPObject.h"

@interface OPDiffieHellman : OPObject {
    
}

/// data to be sent to remote peer
@property (readonly) NSData *AData;

- (SecKeyRef) createKeyWithBData:(NSData *)BData;

@end
