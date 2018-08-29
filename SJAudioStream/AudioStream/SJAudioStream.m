//
//  SJAudioStream.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/28.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioStream.h"
#import <CFNetwork/CFNetwork.h>
#import <pthread.h>


@interface SJAudioStream ()

@property (nonatomic, assign) NSUInteger contentLength;

@property (nonatomic, assign) SInt64 byteOffset;

@property (nonatomic, strong) NSDictionary *httpHeaders;

@property (nonatomic, assign) CFReadStreamRef readStream;

@property (nonatomic, weak)   id<SJAudioStreamDelegate> delegate;

@end


@implementation SJAudioStream


- (instancetype)initWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset delegate:(id<SJAudioStreamDelegate>)delegate
{
    self = [super init];
    
    if (self)
    {
        self.byteOffset = byteOffset;
        
        self.delegate = delegate;
        
        CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(url), kCFHTTPVersion1_1);
        
        // If we are creating this request to seek to a location, set the requested byte range in the headers.
        if (self.byteOffset > 0)
        {
            NSString *range = [NSString stringWithFormat:@"bytes=%lld-", self.byteOffset];
            
            CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef _Nullable)(range));
        }
        
        // create the read stream that will receive data from the HTTP request.
        self.readStream = CFReadStreamCreateForHTTPRequest(NULL, message);
        
        CFRelease(message);
        
        Boolean success = CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
        
        if (!success)
        {
            // 错误处理
            NSLog(@"error: failed to set `HTTPShouldAutoredirect` property of the readStream.");
        }
        
        // Handle proxies
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPProxy, proxySettings);
        CFRelease(proxySettings);
        
        // Handle SSL connections
        if ([[url scheme] isEqualToString:@"https"])
        {
            NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES), kCFStreamSSLValidatesCertificateChain, [NSNull null], kCFStreamSSLPeerName, nil];
            
            CFReadStreamSetProperty(self.readStream, kCFStreamPropertySSLSettings, (__bridge CFDictionaryRef)(sslSettings));
        }
        
        // open the readStream
        success = CFReadStreamOpen(self.readStream);
        
        if (!success)
        {
            CFRelease(self.readStream);
            
            // 错误处理
            NSLog(@"error: failed to open the readStream.");
        }
        
        CFStreamClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        
        CFReadStreamSetClient(self.readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
        
        CFReadStreamScheduleWithRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
    
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error
{
    UInt8 bytes[maxLength];
    
    // 如果当前还没有数据可供读取，此函数会阻塞调用线程直到有数据可供读取。
    CFIndex length = CFReadStreamRead(self.readStream, bytes, maxLength);
    
    if (length == -1)
    {
        // 错误处理
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:nil];
        
        return nil;
        
    }else if (length == 0)
    {
        return nil;
    }
    
    if (!self.httpHeaders)
    {
        CFTypeRef message = CFReadStreamCopyProperty(self.readStream, kCFStreamPropertyHTTPResponseHeader);
        
        self.httpHeaders = (__bridge NSDictionary *)(CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message));
        
        CFRelease(message);
        
        // 音频文件总长度
        self.contentLength = [[self.httpHeaders objectForKey:@"Content-Length"] integerValue] + (NSUInteger)self.byteOffset;
    }
    
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    
    return data;
}


- (void)closeReadStream
{
    CFReadStreamClose(self.readStream);
    
    CFReadStreamUnscheduleFromRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    CFReadStreamSetClient(self.readStream, kCFStreamEventNone, NULL, NULL);
}


#pragma mark- SJReadStreamCallBack
static void SJReadStreamCallBack (CFReadStreamRef aStream, CFStreamEventType eventType, void *inClientInfo)
{
    SJAudioStream *audioStream = (__bridge SJAudioStream *)inClientInfo;
    
    [audioStream handleReadFromStream:aStream eventType:eventType];
}

- (void)handleReadFromStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    switch (eventType)
    {
        case kCFStreamEventHasBytesAvailable:
        {
            [self.delegate audioStreamHasBytesAvailable:self];
        }
            break;
            
        case kCFStreamEventErrorOccurred:
        {
            [self.delegate audioStreamErrorOccurred:self];
        }
            break;
            
        case kCFStreamEventEndEncountered:
        {
            [self.delegate audioStreamEndEncountered:self];
        }
            break;
            
        default:
            
            break;
    }
}

@end
