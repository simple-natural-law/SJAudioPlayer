//
//  SJHttpStream.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/28.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJHttpStream.h"
#import <CFNetwork/CFNetwork.h>
#import <pthread.h>
#import <sys/time.h>


@interface SJHttpStream ()
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, assign) CFStreamEventType streamEvent;

@property (nonatomic, strong) NSDictionary *httpHeaders;

@property (nonatomic, assign) BOOL closed;

@property (nonatomic, assign) CFReadStreamRef readStream;

@end


@implementation SJHttpStream

#pragma mark- ReadStream callback
void SJReadStreamCallBack (CFReadStreamRef stream,CFStreamEventType eventType,void * clientCallBackInfo)
{
    SJHttpStream *httpStream = (__bridge SJHttpStream *)(clientCallBackInfo);
    
    [httpStream handleReadFormStream:stream eventType:eventType];
}

- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithURL:(NSURL *)url byteOffset:(NSUInteger)byteOffset
{
    self = [super init];
    
    if (self)
    {
        self.closed = YES;
        
        // 创建CHFHTTP消息对象
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
            NSLog(@"CFReadStreamSetProperty error.");
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
            NSLog(@"CFReadStreamOpen error.");
        }
        
        self.closed = NO;
        
        // set our callback function to receive the data
        //CFStreamClientContext context = {0,(__bridge void *)(self),NULL,NULL,NULL};
        
        //CFReadStreamSetClient(_readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
        
        // 在当前线程回调
        //CFReadStreamScheduleWithRunLoop(_readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}

- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error completed:(BOOL *)completed
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
        
        NSLog(@"");
        
        return nil;
        
    }else if (length == 0)
    {
        *completed = YES;
        
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


- (void)close
{
    self.closed = YES;
}


- (void)handleReadFormStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    self.streamEvent = eventType;
}

@end
