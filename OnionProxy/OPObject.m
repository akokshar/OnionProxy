//
//  OPObject.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 02/03/14.
//
//

#import "OPObject.h"
#import "OPSHA1.h"
#import "OPSHA256.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

@interface OPObject() {
    
}

@end

@implementation OPObject

@synthesize options = _options;

- (NSMutableDictionary *) getOptions {
    @synchronized(self) {
        if (_options == NULL) {
            _options = [NSMutableDictionary dictionary];
        }
    }
    return _options;
}

- (void) logMsg:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    printf("[%s] %s\n", (const char *)[self.name UTF8String], (const char *)[message UTF8String]);
    [message release];
    va_end(args);
}

- (NSData *) decodeBase64Str:(NSString *)str {
    return [[[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
}

- (NSString *) hexStringFromData:(NSData *)data {
    NSMutableString *hexString = [[NSMutableString alloc] initWithCapacity:[data length] * 2];
    const unsigned char *bytes = [data bytes];
    for (int i = 0; i < [data length]; i++) {
        [hexString appendFormat:@"%02X", bytes[i]];
    }
    
    return [hexString autorelease];
}

- (id) init {
    self = [super init];
    if (self) {
        self.name = @"OPObject";
    }
    return self;
}

- (void) dealloc {
    if (_options) {
        [_options release];
    }
    self.name = NULL;
    
    [super dealloc];
}

@end
