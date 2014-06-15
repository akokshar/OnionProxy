//
//  OPTorDirectoryObject.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 14/06/14.
//
//

#import "OPObject.h"

@interface OPTorDirectoryObject : OPObject {

}

- (BOOL) downloadResource:(NSString *)resource to:(NSString *)file;

@end
