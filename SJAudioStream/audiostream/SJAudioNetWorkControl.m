//
//  SJAudioNetWorkControl.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/3/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioNetWorkControl.h"
#import <pthread.h>
#import <sys/time.h>

#define NETWORK_TIMEOUT 60

@implementation SJAudioNetWorkControl
{
    NSUInteger _byteoffset;
    CFReadStreamRef _stream;
    pthread_cond_t _cond;
    pthread_mutex_t _mutex;
    CFStreamEventType _streamEvent;
    NSDictionary *_httpHeaders;
    BOOL _closed;
}

- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
    CFReadStreamClose(_stream);
    CFRelease(_stream);
    _stream = nil;
}


- (instancetype)initWithURL:(NSURL *)url byteoffset:(NSUInteger)byteoffset
{
    self = [super init];
    
    if (self) {
        _closed = YES;
        
        CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(url), kCFHTTPVersion1_1);
        
        _byteoffset = byteoffset;
        
        if (_byteoffset) {
            
            CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef)[NSString stringWithFormat:@"bytes=%lu-", (unsigned long)_byteoffset]);
        }
        
        _stream = CFReadStreamCreateForHTTPRequest(NULL, message);
        
        CFRelease(message);
        
        if (CFReadStreamSetProperty(_stream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue) == false) {
            
            //错误处理
            return nil;
        }
        
        // Handle proxies
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        
        CFReadStreamSetProperty(_stream, kCFStreamPropertyHTTPProxy, proxySettings);
        
        CFRelease(proxySettings);
        
        // Handle SSL connections
        if ([[url absoluteString] rangeOfString:@"https"].location != NSNotFound) {
            
            NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES), kCFStreamSSLValidatesCertificateChain,[NSNull null],kCFStreamSSLPeerName,nil];
            
            CFReadStreamSetProperty(_stream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(sslSettings));
        }
        
        // open the readStream
        if (!CFReadStreamOpen(_stream)) {
            CFRelease(_stream);
            
            // 错误处理
            
            return nil;
        }
        
        _closed = NO;
        
        // set our callback function to receive the data
        CFStreamClientContext context = {0,(__bridge void *)(self),NULL,NULL,NULL};
        
        CFReadStreamSetClient(_stream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
        
        CFReadStreamScheduleWithRunLoop(_stream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        
        // 初始化锁
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}

// call back
static void SJReadStreamCallBack(CFReadStreamRef aStream, CFStreamEventType eventType,void* inClientInfo)
{
    
    SJAudioNetWorkControl *networkStream = (__bridge SJAudioNetWorkControl *)(inClientInfo);
    
    [networkStream handleReadFromStream:aStream eventType:eventType];
    
}

- (void)handleReadFromStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    pthread_mutex_lock(&_mutex);
    _streamEvent = eventType;
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}

- (void)close
{
    pthread_mutex_lock(&_mutex);
    _closed = YES;
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}


- (NSData *)readDataWithMaxlength:(NSUInteger)maxLength error:(NSError *__autoreleasing *)error
{
    int              rc;
    struct timespec  ts;
    struct timeval   tp;
    
    rc = pthread_mutex_lock(&_mutex);
    rc = gettimeofday(&tp, NULL);
    
    // 把 timeval 转换成 timespec
    ts.tv_sec  = tp.tv_sec;
    ts.tv_nsec = tp.tv_usec * 1000;
    ts.tv_sec += NETWORK_TIMEOUT;
    
    while (!_closed && _streamEvent == kCFStreamEventNone) {
        <#statements#>
    }
}

@end
