//
//  OPHTTPStream.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 07/04/14.
//
//

#import "OPStream.h"
#import "OPTorNetwork.h"

NSString * const kOPHTTPStreamContentEncodingKey = @"Content-Encoding";
NSString * const kOPHTTPStreamAcceptEncodingKey = @"Accept-Encoding";

@interface OPStream()

@property (assign) BOOL isClosed;
@property (assign) BOOL isForDirectoryService;
@property (retain) OPCircuit *circuit;
@property (retain) id<OPHTTPStreamDelegate> client;
@property (assign) OPStreamId streamId;
@property (retain) NSString *destIp;
@property (assign) uint16 destPort;

@property (retain) NSURLRequest *request;
@property (retain) NSHTTPURLResponse *response;
@property (retain) NSMutableData *headerData;
@property (retain) NSMutableData *contentData;
@property (retain) NSString *contentEncoding;

- (void) receiveHeaderData:(NSData *)data;
- (void) receiveContentData:(NSData *)data;
- (NSData *) decompressData:(NSData *)data;

@end

@implementation OPStream

- (void) open {
    @synchronized(self) {
        if (self.isClosed) {
            [self logMsg:@"Attempt to open already closed HTTP stream"];
            return;
        }
        if (self.streamId != 0) {
            [self logMsg:@"Attempt to open stream twice"];
            return;
        }
        if (self.isForDirectoryService) {
            self.streamId = [self.circuit openDirectoryStreamWithDelegate:self];
        }
        else {
            [self logMsg:@"!!! only directory streams realized so far !!!"];
        }
    }
}

- (void) close {
    @synchronized(self) {
        if (self.streamId == 0) {
            return;
        }
        [self.circuit closeStream:self.streamId];
        self.streamId = 0;
        self.isClosed = YES;
    }
}

- (void) sendData:(NSData *)data {
    [self.circuit sendData:data overStream:self.streamId];
}

- (NSData *) decompressData:(NSData *)data {
    NSData *decompressedData = NULL;
    if (self.contentEncoding) {
        if ([self.contentEncoding isCaseInsensitiveLike:@"deflate"]) {
            SecTransformRef decodeTransform = SecDecodeTransformCreate(kSecZLibEncoding, NULL);
            if (decodeTransform == NULL) {
                return NULL;
            }
            SecTransformSetAttribute(decodeTransform, kSecTransformInputAttributeName, data, NULL);
            decompressedData = SecTransformExecute(decodeTransform, NULL);
            CFRelease(decodeTransform);
        }
        else if ([self.contentEncoding isCaseInsensitiveLike:@"gzip"]) {
            //TODO: decompress gzip
            //SecTransformSetAttribute(decodeTransform, kSecDecodeTypeAttribute, kSecGZipEncoding, NULL);
        }
    }
    return decompressedData;
}

- (void) receiveHeaderData:(NSData *)data {
    BOOL isNoError = YES;
    [self.headerData appendData:data];

    NSData *delimeter = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange headerEnd = [data rangeOfData:delimeter options:0 range:NSMakeRange(0, [data length])];

    if (headerEnd.location != NSNotFound) {
        NSUInteger httpHeaderLen = [self.headerData length] - [data length] + headerEnd.location + headerEnd.length;
        NSData *httpHeaderData = [self.headerData subdataWithRange:NSMakeRange(0, httpHeaderLen)];
        NSString *httpHeaderStr = [[NSString alloc] initWithData:httpHeaderData encoding:NSUTF8StringEncoding];

        NSRegularExpressionOptions optionsRegEx = (NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnixLineSeparators);
        // $1-Version, $2-Code, $4-headers
        NSString *httpHeaderPattern = @"(\\S+)\\s+(\\d+)\\s+(.*?)\\r\\n(.*)";

        NSRegularExpression *httpHeaderRegEx = [NSRegularExpression regularExpressionWithPattern:httpHeaderPattern options:optionsRegEx error:NULL];
        if (httpHeaderRegEx) {
            NSArray *httpHeaderMatch = [httpHeaderRegEx matchesInString:httpHeaderStr options:NSMatchingAnchored range:NSMakeRange(0, [httpHeaderStr length])];

            if ([httpHeaderMatch count] == 1) {
                NSTextCheckingResult *match = [httpHeaderMatch objectAtIndex:0];
                NSString *httpVersion = [httpHeaderStr substringWithRange:[match rangeAtIndex:1]];
                NSInteger httpError = [[httpHeaderStr substringWithRange:[match rangeAtIndex:2]] integerValue];

                NSMutableDictionary *headerFields = [NSMutableDictionary dictionary];
                NSString *headerFieldsStr = [httpHeaderStr substringWithRange:[match rangeAtIndex:4]];
                NSString *headerFieldsPattern = @"(.*?):(.*?)\\r\\n";

                NSRegularExpression *headerFieldsRegEx = [NSRegularExpression regularExpressionWithPattern:headerFieldsPattern options:optionsRegEx error:NULL];
                if (headerFieldsRegEx) {
                    NSArray *headerFieldsMatch = [headerFieldsRegEx matchesInString:headerFieldsStr options:NSMatchingReportProgress range:NSMakeRange(0, [headerFieldsStr length])];

                    for (NSTextCheckingResult *headerFieldMatch in headerFieldsMatch) {
                        NSString *headerName = [headerFieldsStr substringWithRange:[headerFieldMatch rangeAtIndex:1]];
                        NSString *headerValue = [headerFieldsStr substringWithRange:[headerFieldMatch rangeAtIndex:2]];
                        [headerFields setValue:[headerValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                        forKey:[headerName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                    }
                }

                self.contentEncoding = [headerFields objectForKey:kOPHTTPStreamContentEncodingKey];
                [headerFields removeObjectForKey:kOPHTTPStreamContentEncodingKey];

                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:httpError HTTPVersion:httpVersion headerFields:headerFields];
                self.response = response;
                [response release];

                [self.client stream:self didReceiveResponse:self.response];
            }
            else {
                [self logMsg:@"Error. HTTP heades did not match pattern"];
                isNoError = NO;
            }
        }
        else {
            isNoError = NO;
        }

        [httpHeaderStr release];

        if (isNoError) {
            if (httpHeaderLen < [self.headerData length]) {
                [self receiveContentData:[data subdataWithRange:NSMakeRange(httpHeaderLen, [data length] - httpHeaderLen)]];
            }
            self.headerData = NULL;
        }
        else {
            //TODO: Failure in this branch
            [self close];
        }
    }
}

- (void) receiveContentData:(NSData *)data {
    if (self.response == NULL) {
        [self logMsg:@"Error. HTTP header is not recived yet."];
    }

    if (!self.contentEncoding || [self.contentEncoding isCaseInsensitiveLike:@"identity"]) {
        [self.client stream:self didReceiveData:data];
    }
    else {
        [self.contentData appendData:data];
    }
}

- (void) streamReceivedData:(NSData *)data {
    if (self.response == NULL) {
        [self receiveHeaderData:data];
    }
    else {
        [self receiveContentData:data];
    }
}

- (void) streamOpened {
    self.headerData = [NSMutableData data];
    self.contentData = [NSMutableData data];

    [self logMsg:@"streamOpened. Sending HTTP request"];

    NSMutableString *requestStr = [NSMutableString string];
    [requestStr appendString:[NSString stringWithFormat:@"%@ %@ HTML/1.1\r\n",
                                self.request.HTTPMethod,
                                self.request.URL.path]];
    [requestStr appendString:@"Accept-Encoding: gzip, deflate\r\n"];

    //TODO: filter header fields
    [[self.request allHTTPHeaderFields] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *keyStr = (NSString *)key;
        NSString *valueStr = (NSString *)obj;
        if (![keyStr isCaseInsensitiveLike:kOPHTTPStreamAcceptEncodingKey]) {
            [requestStr appendFormat:@"%@: %@\r\n", keyStr, valueStr];
        }
    }];

    [requestStr appendString:@"\r\n"];
    [self logMsg:@"%@", requestStr];

    [self sendData:[requestStr dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void) streamClosed {
    [self logMsg:@"streamClosed"];
    if ([self.contentData length] > 0) {
        [self.client stream:self didReceiveData:[self decompressData:self.contentData]];
    }
    [self.client streamDidFinishLoading:self];
}

- (void) streamError {
    [self logMsg:@"streamError"];
    [self.client stream:self didFailWithError:[NSError errorWithDomain:@"OPStreamDomain" code:1001 userInfo:NULL]];
}

- (id) initForDirectoryServiceWithCircuit:(OPCircuit *)circuit client:(id<OPHTTPStreamDelegate>)client request:(NSURLRequest *)request {
    [self logMsg:@"INIT STREAM FOR DIRECTORY SERVICE"];
    self = [super init];
    if (self) {
        self.isForDirectoryService = YES;
        self.isClosed = NO;
        self.circuit = circuit;
        self.client = client;
        self.destIp = NULL;
        self.destPort = 0;
        self.request = request;
    }
    return self;
}

- (id) initWithCircuit:(OPCircuit *)circuit destIp:(NSString *)destIp destPort:(uint16)destPort client:(id<OPHTTPStreamDelegate>)client {
    [self logMsg:@"INIT STREAM"];
    self = [super init];
    if (self) {
        self.isForDirectoryService = NO;
        self.isClosed = NO;
        self.circuit = circuit;
        self.client = client;
        self.destIp = destIp;
        self.destPort = destPort;
    }
    return self;
}

- (void) dealloc {
    [self logMsg:@"DEALLOC STREAM"];
    self.client = NULL;
    self.circuit = NULL;
    self.destIp = NULL;

    self.request = NULL;
    self.response = NULL;
    self.contentData = NULL;
    self.headerData = NULL;

    [super dealloc];
}

+ (OPStream *) streamForClient:(id<OPHTTPStreamDelegate>)client withDirectoryResourceRequest:(NSURLRequest *)request {
    OPCircuit *circuit = [[OPTorNetwork network] circuitForDirectoryService];
    if (circuit) {
        return [[[OPStream alloc] initForDirectoryServiceWithCircuit:circuit client:client request:request] autorelease];
    }
    return NULL;
}

+ (OPStream *) directoryStreamForClient:(id<OPHTTPStreamDelegate>)client {
    return NULL;
}

@end
