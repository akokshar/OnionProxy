//
//  OPHTTPStream.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 07/04/14.
//
//

#import "OPHTTPStream.h"

@interface OPHTTPStream()

@property (assign) BOOL isClosed;
@property (readonly, getter=getIsForDirectoryService) BOOL isForDirectoryService;
@property (retain) OPCircuit *circuit;
@property (assign) OPStreamId streamId;
@property (retain) NSString *destIp;
@property (assign) uint16 destPort;

@end

@implementation OPHTTPStream

@synthesize isForDirectoryService;

- (BOOL) getIsForDirectoryService {
    if (self.destIp == NULL && self.destPort == 0) {
        return YES;
    }
    return NO;
}

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
    [self logMsg:@"Stream sendData '%@'", data];
    [self.circuit sendData:data overStream:self.streamId];
}

- (void) streamReceivedData:(NSData *)data {
    [self logMsg:@"streamReceivedData '%@'", data];
}

- (void) streamOpened {
    [self logMsg:@"streamOpened"];

    NSString *get = @"GET /tor/server/d/49C7897A1AAB314C417B83CD1B79C9A84089AE7B.z HTML/1.1\r\n\r\n";
    [self sendData:[get dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void) streamClosed {
    [self logMsg:@"streamClosed"];
}

- (id) initForDirectoryServiceWithCircuit:(OPCircuit *)circuit client:(id<OPHTTPStreamDelegate>)client {
    [self logMsg:@"INIT STREAM FOR DIRECTORY SERVICE"];
    self = [super init];
    if (self) {
        self.isClosed = NO;
        self.circuit = circuit;
        self.client = client;
        self.destIp = NULL;
        self.destPort = 0;
    }
    return self;
}

- (id) initWithCircuit:(OPCircuit *)circuit destIp:(NSString *)destIp destPort:(uint16)destPort client:(id<OPHTTPStreamDelegate>)client {
    [self logMsg:@"INIT STREAM"];
    self = [super init];
    if (self) {
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
    [super dealloc];
}

@end
