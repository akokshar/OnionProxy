//
//  OPDirectoryStore.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 05/07/14.
//
//

#import "OPObject.h"

@interface OPDirectoryStore : OPObject

+ (OPDirectoryStore *) directoryStore;

- (NSData *) resourceWithPath:(NSString *)path;
- (void) clearResourceWithPath:(NSString *)path;
- (void) clearResourceBefore:(NSDate *)date;

@end
