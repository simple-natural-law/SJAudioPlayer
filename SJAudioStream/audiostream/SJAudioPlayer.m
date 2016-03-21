//
//  SJAudioPlayer.m
//  AudioStreamDemo
//
//  Created by 张诗健 on 16/1/5.
//  Copyright © 2016年 zhangshijian. All rights reserved.
//

/*
  音频播放所需要的步骤：
  1.读取MP3文件 NSDFileHandle
  2.解析采样率，码率，时长等信息，分离MP3中的音频帧 AudioFileStream／AudioFile
  3.对分离出来的音频帧解码得到PCM数据 AudioQueue
  4.对PCM数据进行音效处理（均衡器，混响等，非必须） 此处不做处理
  5.把PCM数据解码成音频信号 AudioQueue
  6.把音频信号交给硬件播放 AudioQueue
  7.重复1-6步直到播放完成。
*/


/*
  同时使用AudioFileStream和AudioFile:
  第一，对于网络流播必须有AudioFileStream的支持，这是因为我们在第四篇中提到过AudioFile在Open时会要求使用者提供数据，如果提供的数据不足会直接跳过并且返回错误码，而数据不足的情况在网络流中很常见，故无法使用AudioFile单独进行网络流数据的解析；
 第二，对于本地音乐播放选用AudioFile更为合适，原因如下：
 AudioFileStream的主要是用在流播放中虽然不限于网络流和本地流，但流数据是按顺序提供的所以AudioFileStream也是顺序解析的，被解析的音频文件还是需要符合流播放的特性，对于不符合的本地文件AudioFileStream会在Parse时返回NotOptimized错误；
 AudioFile的解析过程并不是顺序的，它会在解析时通过回调向使用者索要某个位置的数据，即使数据在文件末尾也不要紧，所以AudioFile适用于所有类型的音频文件；
 
 一款完整功能的播放器应当同时使用AudioFileStream和AudioFile，用AudioFileStream来应对可以进行流播放的音频数据，以达到边播放边缓冲的最佳体验，用AudioFile来处理无法流播放的音频数据，让用户在下载完成之后仍然能够进行播放。
*/

#import "SJAudioPlayer.h"
#import "SJAudioSession.h"
#import "SJAudioFileStream.h"
#import "SJAudioFile.h"
#import "SJAudioOutputQueue.h"
#import "SJAudioBuffer.h"
#import <pthread.h>
#import <UIKit/UIKit.h>
#import "SJHTTPStream.h"


@interface SJAudioPlayer ()<SJAudioFileStreamDelegate>
{
@private
    NSThread *_thread;
    pthread_mutex_t _mutex;  // 互斥锁   多线程中对共享变量的包保护
    pthread_cond_t _cond;    // 条件锁   线程间同步，一般和pthread_mutex_t一起使用，以防止出现逻辑错误，即如果单独使用条件变量，某些情况下（条件变量前后出现对共享变量的读写）会出现问题
    
    SJAudioPlayerStatus _status;
    
    unsigned long long _fileSize;
    unsigned long long _offSet;
//    NSFileHandle *_fileHandle;
    
    UInt32 _bufferSize;
    SJAudioBuffer *_buffer;
    
    SJAudioFile *_audioFile;
    SJAudioFileStream *_audioFileStream;
    SJAudioOutputQueue *_audioQueue;
    
    BOOL _started;
    BOOL _pauseRequired;
    BOOL _stopRequired;
    BOOL _pausedByInterrupt;
    BOOL _usingAudioFile;
    
    BOOL _seekRequired;
    NSTimeInterval _seekTime;
    NSTimeInterval _timeingOffset;
    
    // network
    CFReadStreamRef _readStream;
    NSDictionary *_httpHeaders;
    
    BOOL _isEof;
    
    SJHTTPStream *_httpStream;
}


@end



@implementation SJAudioPlayer

@dynamic status;
@synthesize failed = _failed;
@synthesize fileType = _fileType;
@synthesize url = _url;
@dynamic isPlayingOrWaiting;
@dynamic duration;
@dynamic progress;


#pragma -mark init & dealloc
- (instancetype)initWithUrl:(NSURL *)url fileType:(AudioFileTypeID)fileType
{
    self = [super init];
    
    if (self)
    {
        _status = SJAudioPlayerStatusStopped;
        
        _url = url;
        _fileType = fileType;
        

        [self isUseAudioFileFromURL:_url];
    }
    return self;
}

- (void)isUseAudioFileFromURL:(NSURL *)url
{
    if ([url.scheme isEqualToString:@"file"]) {
        
        _usingAudioFile = YES;
    }
    else if ([url.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [url.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)
    {
        _usingAudioFile = NO;
    }
}


- (void)dealloc
{
    [self cleanUp];
//    [_fileHandle closeFile];
    
}


// 在播放被停止或者出错时会进入到清理流程，这里需要做一大堆操作，清理各种数据，关闭AudioSession，清除各种标记等等
- (void)cleanUp
{
    _isEof = NO;
    
    // reset file
    _offSet = 0;
//    [_fileHandle seekToFileOffset:0];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SJAudioSessionInterruptionNotification object:nil];
    
    // clean buffer
    [_buffer clean];
    
    _usingAudioFile = NO;
    
    // close audioFileStream
    [_audioFileStream close];
    _audioFileStream = nil;
    
    // closse audioFile
    [_audioFile close];
    _audioFile = nil;
    
    // stop audioqueue
    [_audioQueue stop:YES];
    _audioQueue = nil;
    
    // destory mutex & cond
    [self mutexDestory];
    
    _started = NO;
    _timeingOffset = 0;
    _seekTime = 0;
    _seekRequired = NO;
    _pauseRequired = NO;
    _stopRequired = NO;
    
    
    // reset status
    [self setStatusInternal:SJAudioPlayerStatusStopped];
}


#pragma -mark status
- (BOOL)isPlayingOrWaiting
{
    return self.status == SJAudioPlayerStatusPlaying || self.status == SJAudioPlayerStatusWaiting || self.status == SJAudioPlayerStatusFlushing;
}



- (SJAudioPlayerStatus)status
{
    return _status;
}



- (void)setStatusInternal:(SJAudioPlayerStatus)status
{
    if (_status == status) {
        return;
    }
    
    // kvo 手动通知
    [self willChangeValueForKey:@"status"];
    _status = status;
    [self didChangeValueForKey:@"status"];
}


#pragma -mark -mutex
- (void)mutexInit
{
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);
}



- (void)mutexDestory
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


// 阻塞线程
- (void)mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex); // 阻塞在条件变量上
    pthread_mutex_unlock(&_mutex);
}

// 恢复线程
- (void)mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);    // 解除在条件变量上的阻塞
    pthread_mutex_unlock(&_mutex);
}

#pragma -mark thread
- (BOOL)createAudioQueue
{
    if (_audioQueue) {
        return YES;
    }
    
    NSTimeInterval duration = self.duration;
    
    UInt64 audioDataByteCount = _usingAudioFile ? _audioFile.audioDataByteCount : _audioFileStream.audioDataByteCount;
    
    _bufferSize = 0;
    
    if (duration != 0)
    {
        // 设置bufferSize为近似0.2秒的数据量。 audioDataByteCount / duration －》每 1 秒的数据量大小
        
        _bufferSize = (audioDataByteCount / duration) * 0.2;
        
//        _bufferSize = _usingAudioFile ? _audioFile.maxPacketSize : _audioFileStream.maxPacketSize;
    }
    
    if (_bufferSize > 0) {
        
        // 计算bufferSize需要用到的duration和audioDataByteCount可以从MCAudioFileStream或者MCAudioFile中获取。有了bufferSize之后，加上数据格式format参数和magicCookie（部分音频格式需要）就可以生成AudioQueue了
        AudioStreamBasicDescription format = _usingAudioFile ? _audioFile.format : _audioFileStream.format;
        
        NSData *magicCookie = _usingAudioFile ? [_audioFile fetchMagicCookie] : [_audioFileStream fetchMagicCookie];
        
        _audioQueue = [[SJAudioOutputQueue alloc]initWithFormat:format bufferSize:_bufferSize macgicCookie:magicCookie];
        
        if (!_audioQueue.available) {
            
            _audioQueue = nil;
            return NO;
        }
    }
    
    return YES;
}



- (void)threadMain
{
    NSLog(@"%@",[NSThread currentThread]);
    
    _failed = YES;
    
    // 音频播放的第一步，是要创建AudioSession（set audiosession category）
    if ([[SJAudioSession sharedInstance] setCategory:kAudioSessionCategory_MediaPlayback error:NULL]) {
        
        // 启用 audiosession （active audiosession）,并监听interrput通知
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruptHandler:) name:SJAudioSessionInterruptionNotification object:nil];
        
        if (![[SJAudioSession sharedInstance] setActive:YES error:NULL]) {
            
            // 错误处理
            
            return;
        }
        
        _failed = NO;
    }
    
    if (_failed)
    {
        [self cleanUp];
        return;
    }
    
    [self setStatusInternal:SJAudioPlayerStatusWaiting];
    
    _isEof = NO;
    
    while (self.status != SJAudioPlayerStatusStopped && !_failed && _started)
    {
        @autoreleasepool
        {
            if (_audioFileStream.readyToProducePackets)
            {
                if (![self createAudioQueue])
                {
                    _failed = YES;
                    break;
                }
                
                if (!_audioQueue)
                {
                    continue;
                }
                
                if (self.status == SJAudioPlayerStatusFlushing && !_audioQueue.isRuning)
                {
                    break;
                }
                
                @synchronized(self) {
                    
                    //stop
                    if (_stopRequired)
                    {
                        _stopRequired = NO;
                        _started = NO;
                        [_audioQueue stop:YES];
                        break;
                    }
                }
                
                @synchronized(self) {
                    
                    //pause
                    if (_pauseRequired)
                    {
                        [self setStatusInternal:SJAudioPlayerStatusPaused];
                        [_audioQueue pause];
                        
                        [self mutexWait];
                        _pauseRequired = NO;
                    }
                    
                }
                
                @synchronized(self) {
                    
                    //play
                    if ([_buffer bufferedSize] >= _bufferSize || _isEof)
                    {
                        UInt32 packetCount;
                        AudioStreamPacketDescription *desces = NULL;
                        
                        NSData *data = [_buffer dequeueDataWithSize:_bufferSize packetCount:&packetCount descriptions:&desces];
                        
                        if (packetCount != 0)
                        {
                            [self setStatusInternal:SJAudioPlayerStatusPlaying];
                            
                            _failed = ![_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:_isEof];
                            
                            free(desces);
                            
                            if (_failed)
                            {
                                break;
                            }
                            
                            if (![_buffer hasData] && _isEof && _audioQueue.isRuning)
                            {
                                [_audioQueue stop:NO];
                                [self setStatusInternal:SJAudioPlayerStatusFlushing];
                            }
                        }
                        else if (_isEof)
                        {
                            //wait for end
                            if (![_buffer hasData] && _audioQueue.isRuning)
                            {
                                [_audioQueue stop:NO];
                                [self setStatusInternal:SJAudioPlayerStatusFlushing];
                            }
                        }
                        else
                        {
                            _failed = YES;
                            break;
                        }
                    
                    }
                    
                }
                
            }
        }
    }
    
    //clean
    [self cleanUp];
}


- (void)startNetwork
{
    _failed = ![self openReadStream];
    
    NSLog(@"------- %@",[NSThread currentThread]);
    
    BOOL done = YES;
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    [runloop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    do {
//        done = [[NSRunLoop currentRunLoop]
//                runMode:NSDefaultRunLoopMode
//                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        
        [runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        
        @synchronized(self) {
        
            //seek
            if (_seekRequired && self.duration != 0)
            {
                [self setStatusInternal:SJAudioPlayerStatusWaiting];
                
                _timeingOffset = _seekTime - _audioQueue.playedTime;
                
                _offSet = [_audioFileStream seekToTime:&_seekTime];
                
                [self internalSeekToBytesOffSet:_offSet];
                
                _seekRequired = NO;
                [_audioQueue reset];
            }
        }
        
    }while (done && ![self shouldExitRunloop]);
}




- (BOOL)shouldExitRunloop
{
//    @synchronized(self) {
//        
//        if (_isEof || self.status == SJAudioPlayerStatusStopped) {
//            
//            return YES;
//        }
//        
//    }
    
    return NO;
}




#pragma -mark interrupt
// 在接到Interrupt通知时需要处理打断,
// 打断操作放在了主线程进行而并非放到新开的线程中进行，原因如下：
// 一旦打断开始AudioSession被抢占后音频立即被打断，此时AudioQueue的所有操作会暂停，这就意味着不会有任何数据消耗回调产生；
// 这个Demo的线程模型中在向AudioQueue Enqueue了足够多的数据之后会阻塞当前线程等待数据消耗的回调才会signal让线程继续跑；
// 于是就得到了这样的结论：一旦打断开始创建的线程就会被阻塞，所以需要在主线程来处理暂停和恢复播放。
- (void)interruptHandler:(NSNotification *)notification
{
    UInt32 interruptionState = [notification.userInfo[SJAudioSessionInterruptionStateKey] unsignedIntValue];
    
    if (interruptionState == kAudioSessionBeginInterruption) {
        _pausedByInterrupt = YES;
        [_audioQueue pause];
        [self setStatusInternal:SJAudioPlayerStatusPaused];
        
    }else if (interruptionState == kAudioSessionEndInterruption)
    {
        AudioSessionInterruptionType interruptionType = [notification.userInfo[SJAudioSessionInterruptionTypeKey] unsignedIntValue];
        if (interruptionType == kAudioSessionInterruptionType_ShouldResume) {
            
            if (self.status == SJAudioPlayerStatusPaused && _pausedByInterrupt) {
                
                if ([[SJAudioSession sharedInstance] setActive:YES error:NULL]) {
                    
                    [self play];
                }
            }
        }
    }
}



#pragma -mark delegate (parser)
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    @synchronized(self) {
        
        [_buffer enqueueFromDataArray:audioData];
    }
}



#pragma -mark  method
- (void)play
{
    // 不能在主线程进行播放，我们需要创建自己的播放线程。创建一个成员变量_started来表示播放流程是否已经开始，在-play方法中如果_started为NO就创建线程_thread并以-threadMain方法作为main，否则说明线程已经创建并且在播放流程中,接下来就可以在-threadMain进行音频播放相关的操作了.
    if (!_started)
    {
        _started = YES;
        
        [self mutexInit];
        
        // 创建一个全局并发队列来 进行音频数据的请求.
        dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        dispatch_async(globalQueue, ^{
            
            [self startNetwork];
            
        });
        
//        NSThread *networkThread = [[NSThread alloc]initWithTarget:self selector:@selector(startNetwork) object:nil];
//        
//        [networkThread start];
        
        
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        
        [_thread start];
        
    }else
    {
        if (_status == SJAudioPlayerStatusPaused || _pauseRequired) {
            
            _pausedByInterrupt = NO;
            
            _pauseRequired = NO;
            
            if ([[SJAudioSession sharedInstance] setActive:YES error:NULL]) {
                
                [[SJAudioSession sharedInstance] setCategory:kAudioSessionCategory_MediaPlayback error:NULL];
                
                [self resume];
                
            }
        }
    }
}




- (void)resume
{
    [_audioQueue resume];
    [self mutexSignal];
}

//要注意的是 暂停 和 恢复 需要和-playData:同步调用，否则可能引起一些问题（比如触发了pause实际由于并发操作没有真正pause住）。同步的方法可以采用加锁的方式，也可以通过标志位在threadMain中进行Pause，此处使用了后者。
- (void)pause
{
    if (self.isPlayingOrWaiting && self.status != SJAudioPlayerStatusFlushing) {
        _pauseRequired = YES;
    }
}


- (void)stop
{
    _stopRequired = YES;
    [self mutexSignal];
}



#pragma -mark progress
// 使用AudioQueueGetCurrentTime方法可以获取实际播放的时间如果Seek之后需要根据计算timingOffset，然后根据timeOffset来计算最终的播放进度：
- (NSTimeInterval)progress
{
    // 在seek时为了防止播放进度跳动，修改一下获取播放进度的方法
    if (_seekRequired) {
        return _seekTime;
    }
    return _timeingOffset + _audioQueue.playedTime;
}


// seek
- (void)setProgress:(NSTimeInterval)progress
{
    _seekRequired = YES;
    _seekTime = progress;
}



- (NSTimeInterval)duration
{
    return _usingAudioFile ? _audioFile.duration : _audioFileStream.duration;
}


- (void)internalSeekToBytesOffSet:(unsigned long long)offSet
{
    if (_readStream) {
        CFRelease(_readStream);
        _readStream = nil;
    }
    
    @synchronized(self) {
        
        [_audioQueue stop:YES];
        
        [_buffer clean];
        
        _failed = ![self openReadStream];
        
    }
}


#pragma -mark network
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
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    return YES;

}


static void SJReadStreamCallBack(CFReadStreamRef aStream, CFStreamEventType eventType,void* inClientInfo)
{
   
    SJAudioPlayer *audioPlayer = (__bridge SJAudioPlayer *)(inClientInfo);
    
    [audioPlayer handleReadFromStream:aStream eventType:eventType];
    
}



- (void)handleReadFromStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    if (stream != _readStream) {
        return;
    }
    
    NSError *error = nil;
    
    // 错误
    if (eventType == kCFStreamEventErrorOccurred) {
        
        // 错误处理
        
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
    }else if (eventType == kCFStreamEventEndEncountered)// 结束
    {
        
        NSLog(@"------------------");
        
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
        _isEof = YES;
        
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
            
            NSLog(@"%@",[NSThread currentThread]);
        }
        
        if (!_audioFileStream) {
            _audioFileStream = [[SJAudioFileStream alloc]initWithFileType:_fileType fileSize:_fileSize error:&error];
            
            _audioFileStream.delegate = self;
            
            _buffer = [SJAudioBuffer buffer];
        }
        
    }
    
    UInt8 bytes[2048];
    
    CFIndex length;
    
//    @synchronized(self) {
    
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
    
//    }
    
    NSLog(@"+++++++++++++++");

    @synchronized(self) {
    
        // 解析数据
        NSData *data = [NSData dataWithBytes:bytes length:length];
        
        _offSet += length;
        
        if (_offSet >= _fileSize) {
            
            _isEof = YES;
        }
    
    [_audioFileStream parseData:data error:&error];
    
    }
}


@end
