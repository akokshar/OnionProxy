//
//  OPCSP.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 04/04/14.
//
//

#import "OPObject.h"

@interface OPCSP : OPObject {
    
}

@property (readonly, getter = getHandle) CSSM_CSP_HANDLE handle;

+ (OPCSP *) instance;

@end
