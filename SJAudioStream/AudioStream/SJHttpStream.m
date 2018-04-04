//
//  SJHttpStream.m
//  AudioTest
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
    NSUInteger _byteOffset;
    CFReadStreamRef _readStream;
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
    CFStreamEventType _streamEvent;
    NSDictionary *_httpHeaders;
    
    BOOL _closed;
}


@end


@implementation SJHttpStream

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
        _closed = YES;
        
        // 创建CHFHTTP消息对象
        CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(url), kCFHTTPVersion1_1);
        
        // If we are creating this request to seek to a location, set the requested byte range in the headers.
        if (_byteOffset)
        {
            NSString *range = [NSString stringWithFormat:@"bytes=%lu-",(unsigned long)_byteOffset];
            
            CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef _Nullable)(range));
        }
        
        // create the read stream that will receive data from the HTTP request.
        _readStream = CFReadStreamCreateForHTTPRequest(NULL, message);
        
        CFRelease(message);
        
        if (CFReadStreamSetProperty(_readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue) == false)
        {
            // 错误处理
        }
        
        // Handle proxies
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        CFReadStreamSetProperty(_readStream, kCFStreamPropertyHTTPProxy, proxySettings);
        CFRelease(proxySettings);
        
        // Handle SSL connections
        if ([[url scheme] isEqualToString:@"https"])
        {
            NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES),kCFStreamSSLValidatesCertificateChain,[NSNull null],kCFStreamSSLPeerName, nil];
            
            CFReadStreamSetProperty(_readStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(sslSettings));
        }
        
        // open the readStream
        if (!CFReadStreamOpen(_readStream))
        {
            CFRelease(_readStream);
            
            // 错误处理
        }
        
        _closed = NO;
        
        // set our callback function to receive the data
        CFStreamClientContext context = {0,(__bridge void *)(self),NULL,NULL,NULL};
        
        CFReadStreamSetClient(_readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
        
        // 在主线程回调
        CFReadStreamScheduleWithRunLoop(_readStream, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}

- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength isEof:(BOOL *)isEof
{
    int                 rc;
    struct timespec     ts;
    struct timeval      tp;
    
    rc = pthread_mutex_lock(&_mutex);
    rc = gettimeofday(&tp, NULL);
    
    // 把 timeval 转换成 timespec
    ts.tv_sec  = tp.tv_sec;
    ts.tv_nsec = tp.tv_usec * 1000;
    ts.tv_sec += HTTP_REQUEST_TIMEOUT;  // 请求超时的时间
    
    // 当开始读取数据，并且还没有接收到数据时，锁住线程，等待streamCallBack所在线程唤醒此线程。或者请求超时，此线程会自动结束等待(唤醒)。
    while (!_closed && _streamEvent == kCFStreamEventNone && !CFReadStreamHasBytesAvailable(_readStream))
    {
        int status = pthread_cond_timedwait(&_cond, &_mutex, &ts);
        
        // 返回0表示经过一段时间解除阻塞。返回ETIMEDOUT，表示超时。出错，返回错误值.
        if (status != 0)
        {
            pthread_mutex_unlock(&_mutex);
            return nil;
        }else if (status == ETIMEDOUT) // 请求超时
        {
            pthread_mutex_unlock(&_mutex);
            return nil;
        }
    }
    
    if (_closed)
    {
        pthread_mutex_unlock(&_mutex);
        return nil;
    }
    
    if (_streamEvent == kCFStreamEventEndEncountered)
    {
        pthread_mutex_unlock(&_mutex);
        
        *isEof = YES;
        
        return nil;
    }
    
    if (_streamEvent == kCFStreamEventErrorOccurred)
    {
        pthread_mutex_unlock(&_mutex);
        return nil;
    }
    
    UInt8 *bytes = (UInt8 *)malloc(maxLength);
    
    CFIndex length = CFReadStreamRead(_readStream, bytes, maxLength);
    
    _streamEvent = kCFStreamEventNone;
    
    pthread_mutex_unlock(&_mutex);
    
    if (length == -1)
    {
        // 错误处理
        
        return NULL;
        
    }else if (length == 0)
    {
        return NULL;
    }
    
    
    if (!_httpHeaders)
    {
        CFTypeRef message = CFReadStreamCopyProperty(_readStream, kCFStreamPropertyHTTPResponseHeader);
        
        _httpHeaders = (__bridge NSDictionary *)(CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message));
        
        CFRelease(message);
        
        // 音频文件总长度
        _contentLength = [[_httpHeaders objectForKey:@"Content-Length"] integerValue] + _byteOffset;
    }
    
    
    NSData *data = [NSData dataWithBytes:bytes length:length];
    
    free(bytes);
    
    return data;
}



- (void)close
{
    pthread_mutex_lock(&_mutex);
    _closed = YES;
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}


- (void)handleReadFormStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    pthread_mutex_lock(&_mutex);
    _streamEvent = eventType;
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}


#pragma mark -readStream callback
void SJReadStreamCallBack (CFReadStreamRef stream,CFStreamEventType eventType,void * clientCallBackInfo)
{
    SJHttpStream *httpStream = (__bridge SJHttpStream *)(clientCallBackInfo);
    
    [httpStream handleReadFormStream:stream eventType:eventType];
}


@end
