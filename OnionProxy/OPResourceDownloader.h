//
//  OPURLDownload.h
//  OnionProxy
//
//  Created by Koksharov Alexander on 12/03/14.
//
//

#import <Foundation/Foundation.h>

#import "OPObject.h"

@interface OPResourceDownloader : OPObject <NSURLDownloadDelegate> {
    
}

+ (BOOL) downloadFromIp:(NSString *)ip port:(NSUInteger)port resource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout;
+ (BOOL) downloadResource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout;
+ (BOOL) downloadFromAuthorityResource:(NSString *)resource to:(NSString *)file timeout:(NSUInteger)timeout;

@end
