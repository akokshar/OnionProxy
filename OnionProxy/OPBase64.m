//
//  OPBase64.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 18/05/14.
//
//

#import "OPBase64.h"

@implementation OPBase64

+ (NSData *) decodeString:(NSString *)str{
    return [[[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
}

+ (NSString *) encodeData:(NSData *)data {
    return [data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
}

@end
