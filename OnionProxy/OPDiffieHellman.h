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

@property (readonly, getter = getEData) NSData *EData;
@property (readonly) NSData *keyData;

@end
