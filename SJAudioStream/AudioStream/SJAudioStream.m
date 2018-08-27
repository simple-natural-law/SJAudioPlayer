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
#import <sys/time.h>


@interface SJAudioStream ()

@property (nonatomic, assign) NSUInteger contentLength;

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, strong) NSDictionary *httpHeaders;

@property (nonatomic, assign) BOOL closed;

@property (nonatomic, assign) CFReadStreamRef readStream;

@property (nonatomic, strong) dispatch_semaphore_t semaphore;

@end


@implementation SJAudioStream


- (instancetype)initWithURL:(NSURL *)url byteOffset:(NSUInteger)byteOffset
{
    self = [super init];
    
    if (self)
    {
        self.closed = YES;
        
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
        
        Boolean status = CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
        
        if (!status)
        {
            // 错误处理
            NSLog(@"error: failed to set property of the readStream.");
        }
        
        // Handle proxies
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPProxy, proxySettings);
        CFRelease(proxySettings);
        
        // Handle SSL connections
        if ([[url scheme] isEqualToString:@"https"])
        {
            NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES),kCFStreamSSLValidatesCertificateChain,[NSNull null],kCFStreamSSLPeerName, nil];
            
            CFReadStreamSetProperty(self.readStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(sslSettings));
        }
        
        // open the readStream
        status = CFReadStreamOpen(self.readStream);
        
        if (!status)
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
        self.contentLength = [[self.httpHeaders objectForKey:@"Content-Length"] integerValue] + self.byteOffset;
    }
    
    NSData *data = [NSData dataWithBytes:bytes length:length];
    
    free(bytes);
    
    return data;
}


- (void)closeReadStream
{
    self.closed = YES;
    
    CFReadStreamClose(self.readStream);
}

@end
