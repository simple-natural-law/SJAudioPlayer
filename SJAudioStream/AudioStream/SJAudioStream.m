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

@end


@implementation SJAudioStream


- (instancetype)initWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset
{
    self = [super init];
    
    if (self)
    {
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
        
        self.closed = NO;
    }
    
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error isEof:(BOOL *)isEof
{
    if (self.closed)
    {
        return nil;
    }
    
    UInt8 *bytes = (UInt8 *)malloc(maxLength);
    
    // 如果当前还没有数据可供读取，此函数会阻塞调用线程直到有数据可供读取。
    CFIndex length = CFReadStreamRead(self.readStream, bytes, maxLength);
    
    if (length == -1)
    {
        // 错误处理
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:nil];
        
        return nil;
        
    }else if (length == 0)
    {
        *isEof = YES;
        
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


@end
