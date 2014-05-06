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

@property (readonly, getter = getRequest) NSData *request;
- (NSData *) deriveSimmetricKeyDataWithResonse:(NSData *)response;

@end
