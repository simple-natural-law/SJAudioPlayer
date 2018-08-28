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

@property (nonatomic, assign) BOOL closed;

@property (nonatomic, assign) CFReadStreamRef readStream;

@property (nonatomic, weak)   id<SJAudioStreamDelegate> delegate;

@end


@implementation SJAudioStream


- (instancetype)initWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset delegate:(id<SJAudioStreamDelegate>)delegate
{
    self = [super init];
    
    if (self)
    {
        self.delegate = delegate;
        
        self.closed = YES;
        
        self.byteOffset = byteOffset;
        
        CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(url), kCFHTTPVersion1_1);
        
        // If we are creating this request to seek to a location, set the requested byte range in the headers.
        if (self.byteOffset)
        {
            NSString *range = [NSString stringWithFormat:@"bytes=%lu-",(unsigned long)self.byteOffset];
            
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
        
        // 在主线程回调
        CFReadStreamScheduleWithRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        
        self.closed = NO;
    }
    
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error
{
    if (self.closed)
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
    
    UInt8 *bytes = (UInt8 *)malloc(maxLength);
    
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
    
    NSData *data = [NSData dataWithBytes:bytes length:length];
    
    free(bytes);
    
    return data;
}


- (void)closeReadStream
{
    self.closed = YES;
    
    CFReadStreamClose(self.readStream);
    
    CFReadStreamUnscheduleFromRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}


#pragma mark- SJReadStreamCallBack
void SJReadStreamCallBack (CFReadStreamRef stream,CFStreamEventType eventType,void * clientCallBackInfo)
{
    SJAudioStream *audioStream = (__bridge SJAudioStream *)(clientCallBackInfo);
    
    switch (eventType)
    {
        case kCFStreamEventHasBytesAvailable:
        {
            [audioStream.delegate audioReadStreamHasBytesAvailable:audioStream];
        }
            break;
            
        case kCFStreamEventErrorOccurred:
        {
            NSLog(@"kCFStreamEventErrorOccurred");
            
            [audioStream.delegate audioReadStreamErrorOccurred:audioStream];
        }
            break;
            
        case kCFStreamEventEndEncountered:
        {
            NSLog(@"kCFStreamEventEndEncountered");
            
            [audioStream.delegate audioReadStreamEndEncountered:audioStream];
        }
            break;
            
        default:
            break;
    }
}


@end
