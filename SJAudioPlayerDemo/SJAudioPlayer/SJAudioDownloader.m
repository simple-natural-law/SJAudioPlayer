//
//  SJAudioDownloader.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/20.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import "SJAudioDownloader.h"
#import <CFNetwork/CFNetwork.h>


static UInt32 const kReadDataMaxLength = 20480; // 1024 * 20


@interface SJAudioDownloader()

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, assign) SInt64 byteOffset;

@property (nonatomic, weak)   id<SJAudioDownloaderDelegate> delegate;

@property (nonatomic, assign) CFReadStreamRef readStream;

@property (nonatomic, strong) NSDictionary *httpHeaders;

@end




@implementation SJAudioDownloader



+ (instancetype)downloadAudioWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset delegate:(id<SJAudioDownloaderDelegate>)delegate
{
    SJAudioDownloader *downloader = [[SJAudioDownloader alloc] initWithURL:url byteOffset:byteOffset delegate:delegate];
    
    BOOL success = [downloader createHTTPRequest];
    
    return success ? downloader : nil;
}




- (instancetype)initWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset delegate:(id<SJAudioDownloaderDelegate>)delegate
{
    self = [super init];
    
    if (self)
    {
        self.url = url;
        
        self.byteOffset = byteOffset;
        
        self.delegate = delegate;
    }
    
    return self;
}




- (BOOL)createHTTPRequest
{
    CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef _Nonnull)(self.url), kCFHTTPVersion1_1);
    
    // If we are creating this request to seek to a location, set the requested byte range in the headers.
    if (self.byteOffset > 0)
    {
        NSString *range = [NSString stringWithFormat:@"bytes=%lld-", self.byteOffset];
        
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef _Nullable)(range));
    }
    
    // create the read stream that will receive data from the HTTP request.
    self.readStream = CFReadStreamCreateForHTTPRequest(NULL, message);
    
    CFRelease(message);
    
    // HTTP auto redirect
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    
    // Handle proxies
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyHTTPProxy, proxySettings);
    
    CFRelease(proxySettings);
    
    // Handle SSL connections
    if ([[self.url scheme] isEqualToString:@"https"])
    {
        NSDictionary *sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:@(YES), kCFStreamSSLValidatesCertificateChain, [NSNull null], kCFStreamSSLPeerName, nil];
        
        CFReadStreamSetProperty(self.readStream, kCFStreamPropertySSLSettings, (__bridge CFDictionaryRef)(sslSettings));
    }
    
    // open the readStream
    Boolean success = CFReadStreamOpen(self.readStream);
    
    if (success)
    {
        CFStreamClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        
        CFReadStreamSetClient(self.readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, SJReadStreamCallBack, &context);
        
        CFReadStreamScheduleWithRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        
        return YES;
        
    }else
    {
        CFRelease(self.readStream);
        
        return NO;
    }
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength
{
    UInt8 bytes[maxLength];
    
    // 如果当前还没有数据可供读取，此函数会阻塞调用线程。
    CFIndex length = CFReadStreamRead(self.readStream, bytes, maxLength);
    
    // 发生错误
    if (length == -1)
    {
        return nil;
    }
    
    // 数据已经全部读取完毕
    if (length == 0)
    {
        return nil;
    }
    
    if (self.httpHeaders == nil)
    {
        CFTypeRef message = CFReadStreamCopyProperty(self.readStream, kCFStreamPropertyHTTPResponseHeader);
        
        self.httpHeaders = (__bridge NSDictionary *)(CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message));
        
        CFRelease(message);
        
        // 音频文件总长度
        unsigned long long contentLength = [[self.httpHeaders objectForKey:@"Content-Length"] longLongValue] + self.byteOffset;
        
        [self.delegate downloader:self getAudioContentLength:contentLength];
    }
    
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    
    return data;
}



- (void)cancelDownload
{
    [self closeReadStream];
}



- (void)closeReadStream
{
    CFReadStreamClose(self.readStream);
    
    CFReadStreamUnscheduleFromRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    CFReadStreamSetClient(self.readStream, kCFStreamEventNone, NULL, NULL);
    
    CFRelease(self.readStream);
}




#pragma mark- SJReadStreamCallBack
static void SJReadStreamCallBack (CFReadStreamRef aStream, CFStreamEventType eventType, void *inClientInfo)
{
    SJAudioDownloader *downloader = (__bridge SJAudioDownloader *)inClientInfo;
    
    [downloader handleReadFromStream:aStream eventType:eventType];
}


- (void)handleReadFromStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    switch (eventType)
    {
        case kCFStreamEventHasBytesAvailable:
        {
            NSData *data = [self readDataWithMaxLength:kReadDataMaxLength];
            
            if (data)
            {
                [self.delegate downloader:self didReceiveData:data];
            }
        }
            break;
            
        case kCFStreamEventErrorOccurred:
        {
            [self closeReadStream];
            
            [self.delegate downloaderErrorOccurred:self];
        }
            break;
            
        case kCFStreamEventEndEncountered:
        {
            [self closeReadStream];
            
            [self.delegate downloaderDidFinished:self];
        }
            break;
            
        default:
            
            break;
    }
}

@end
