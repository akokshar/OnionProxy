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
@property (retain) id<OPStreamDelegate> client;
@property (assign) OPStreamId streamId;
@property (retain) NSString *destIp;
@property (assign) uint16 destPort;

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

        //TODO: check if stream was disconnected or not
        [self.circuit closeStream:self.streamId];
        self.streamId = 0;
        self.isClosed = YES;
    }
}

- (void) sendData:(NSData *)data {
    [self.circuit sendData:data overStream:self.streamId];
}

- (void) streamDidReceiveData:(NSData *)data {
    [self.client stream:self didReceiveData:data];
}

- (void) streamOpened {
    [self.client streamDidConnect:self];
}

- (void) streamClosed {
    [self.client streamDidDisconnect:self];
}

- (void) streamError {
    [self logMsg:@"streamError"];
    [self.client stream:self didFailWithError:[NSError errorWithDomain:@"OPStreamDomain" code:1001 userInfo:NULL]];
}

- (id) initDirectoryStreamWithCircuit:(OPCircuit *)circuit client:(id<OPStreamDelegate>)client {
    [self logMsg:@"INIT STREAM FOR DIRECTORY SERVICE"];
    self = [super init];
    if (self) {
        self.isForDirectoryService = YES;
        self.isClosed = NO;
        self.circuit = circuit;
        self.client = client;
    }
    return self;
}

- (id) initWithCircuit:(OPCircuit *)circuit destIp:(NSString *)destIp destPort:(uint16)destPort client:(id<OPStreamDelegate>)client {
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

    [super dealloc];
}

+ (OPStream *) directoryStreamForClient:(id<OPStreamDelegate>)client {
    OPCircuit *circuit = [[OPTorNetwork network] circuitForDirectoryService];
    if (circuit) {
        return [[[OPStream alloc] initDirectoryStreamWithCircuit:circuit client:client] autorelease];
    }
    return NULL;
}

+ (OPStream *) streamToPort:(uint16)port forClient:(id<OPStreamDelegate>)client {
    //TODO: test code. 
    return [OPStream directoryStreamForClient:client];
}


@end
