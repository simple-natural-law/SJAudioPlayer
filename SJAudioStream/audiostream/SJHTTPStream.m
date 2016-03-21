//
//  SJHTTPStream.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/21.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJHTTPStream.h"

@interface SJHTTPStream ()
{
    unsigned long long _fileSize;
    unsigned long long _offSet;
    
    NSURL *_url;
    
    CFReadStreamRef _readStream;
    NSDictionary *_httpHeaders;
}

@end

@implementation SJHTTPStream

//+ (SJHTTPStream *)shareHttpStream
//{
//    static SJHTTPStream *httpStream = nil;
//    
//    static dispatch_once_t onceToken;
//    
//    dispatch_once(&onceToken, ^{
//        
//        @synchronized(self) {
//            
//            httpStream = [[SJHTTPStream alloc]init];
//        }
//        
//    });
//    
//    return httpStream;
//}


- (instancetype)initWithURL:(NSURL *)url
{
    self = [super init];
    
    if (self) {
        
        _url = url;
        
    }
    
    return self;
}


- (BOOL)openReadStream
{
    // creat the http GET request  创建http请求
    
    /*
     使用以下函数生成一个CFHTTP消息对象：
     
     CFN_EXPORT CFHTTPMessageRef
     CFHTTPMessageCreateRequest(CFAllocatorRef __nullable alloc, CFStringRef
     requestMethod, CFURLRef url, CFStringRef httpVersion);
     
     Discussion:
     Create an HTTPMessage from an HTTP method, url and version.
     
     参数1:
     alloc:   A pointer to the CFAllocator which should be used to allocate
     memory for the CF read stream and its storage for values. If
     this reference is not a valid CFAllocator, the behavior is
     undefined.
     
     参数2:
     requestMethod:  A pointer to a CFString indicating the method of request.
     For a"GET" request, for example, the value would be
     CFSTR("GET").
     
     参数3:
     url: A pointer to a CFURL structure created any of the several
     CFURLCreate... functions.  If this parameter is not a pointer
     to a valid CFURL structure, the behavior is undefined.
     
     参数4:
     httpVersion：A pointer to a CFString indicating the version of request.
     
     Result:
     A pointer to the CFHTTPMessage created, or NULL if failed. It is
     caller's responsibilty to release the memory allocated for the
     message.
     */
    
    CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(_url), kCFHTTPVersion1_1);
    
    
    // If we are creating this request to seek to a location, set the requested byte range in the headers.
    if (_fileSize > 0 && _offSet > 0) {
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef)[NSString stringWithFormat:@"bytes=%llu-%llu", _offSet, _fileSize]);
    }
    
    // create the read stream that will receive data from the HTTP request.
    
    _readStream = CFReadStreamCreateForHTTPRequest(NULL, message);
    
    CFRelease(message);
    
    if (CFReadStreamSetProperty(_readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue) == false) {
        
        // 错误处理
        
        return NO;
        
    }
    
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    
    CFReadStreamSetProperty(_readStream, kCFStreamPropertyHTTPProxy, proxySettings);
    
    CFRelease(proxySettings);
    
    // handle SSL connections
    if ([[_url scheme] isEqualToString:@"https"]) {
        
        NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES), kCFStreamSSLValidatesCertificateChain,[NSNull null],kCFStreamSSLPeerName,nil];
        
        CFReadStreamSetProperty(_readStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(sslSettings));
    }
    
    // open the readStream
    if (!CFReadStreamOpen(_readStream)) {
        CFRelease(_readStream);
        
        // 错误处理
        
        return NO;
    }
    
    // set our callback function to receive the data
    CFStreamClientContext context = {0,(__bridge void *)(self),NULL,NULL,NULL};
    
    CFReadStreamSetClient(_readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
    
    CFReadStreamScheduleWithRunLoop(_readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    
//    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    return YES;
    
}


static void SJReadStreamCallBack(CFReadStreamRef aStream, CFStreamEventType eventType,void* inClientInfo)
{
    
    SJHTTPStream *httpStream = (__bridge SJHTTPStream *)(inClientInfo);
    
    [httpStream handleReadFromStream:aStream eventType:eventType];
    
}



- (void)handleReadFromStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    if (stream != _readStream) {
        return;
    }
    
    // 错误
    if (eventType == kCFStreamEventErrorOccurred) {
        
        // 错误处理
        
//        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
    }else if (eventType == kCFStreamEventEndEncountered)// 结束
    {
        
        NSLog(@"------------------");
        
//        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
//        _isEof = YES;
        
    }else if (eventType == kCFStreamEventHasBytesAvailable)// 接收数据
    {
        if (!_httpHeaders) {
            CFTypeRef message = CFReadStreamCopyProperty(_readStream, kCFStreamPropertyHTTPResponseHeader);
            _httpHeaders = (__bridge NSDictionary *)(CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message));
            
            CFRelease(message);
            
            // Only read the content length if we seeked to time zero, otherwise we only have a subset of the total bytes.
            
            if (_offSet == 0) {
                _fileSize = [[_httpHeaders objectForKey:@"Content-Length"] integerValue];
                
                NSLog(@"--------------- %llu",_fileSize);
            }
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(didReceiveHttpHeaders:AndFileSize:)]) {
                
                [self.delegate didReceiveHttpHeaders:_httpHeaders AndFileSize:_fileSize];
            }
            
        }
        
    }
    
    UInt8 bytes[2048];
    
    CFIndex length;
    
    @synchronized(self) {
        
        if (!CFReadStreamHasBytesAvailable(_readStream)) {
            return;
        }
        
        // Read the bytes from the stream
        length = CFReadStreamRead(_readStream, bytes, 2048);
        
        if (length == -1) {
            // 错误处理
            
            return;
        }
        
        if (length == 0) {
            return;
        }
        
    }
    
    NSLog(@"+++++++++++++++");
    
    // 解析数据
    NSData *data = [NSData dataWithBytes:bytes length:length];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(startReceiveData:AndLength:)]) {
        
        [self.delegate startReceiveData:data AndLength:length];
    }
}



@end
