//
//  SJAudioPlayer.m
//  AudioTest
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioPlayer.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import "SJAudioDataProvider.h"
#import "SJAudioFileStream.h"
#import "SJAudioOutputQueue.h"
#import "SJParsedAudioData.h"
#import "SJAudioBuffer.h"


@interface SJAudioPlayer ()<SJAudioFileStreamDelegate>
{
    SJAudioFileStream *_audioFileStream;
    SJAudioOutputQueue *_audioQueue;
    NSString *_cachePath;
    SJAudioDataProvider *_dataProvider;
    SJAudioBuffer *_buffer;
    NSUInteger _byteOffset;
    NSUInteger _bufferSize;
    
    BOOL _started;
    BOOL _pausedByInterrupt;
    BOOL _isEof;
    BOOL _userStop;
    BOOL _seekRequired;
    BOOL _pauseRequired;
    
    NSTimeInterval _seekTime;
    
    dispatch_queue_t _enqueneDataQueue;
    
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
    
    NSMutableData *_audioData;
}

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (void)mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex); // 阻塞
    pthread_mutex_unlock(&_mutex);
}

- (void)mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);    // 解除阻塞
    pthread_mutex_unlock(&_mutex);
}


- (instancetype)init
{
    self = [super init];
    
    if (self) {
        
        _bufferSize = kDefaultBufferSize;
        
        _started = NO;
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}


- (instancetype)initWithUrlString:(NSString *)url cachePath:(NSString *)cachePath
{
    NSAssert(url, @"url should be not nil");
    
    self = [super init];
    
    if (self)
    {
        _urlString        = url;
        _cachePath  = cachePath;
        
        _bufferSize = kDefaultBufferSize;
        
        _started = NO;
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}

// 在播放停止或者出错时会进入到清理流程，这里需要一大堆操作，清理各种数据，关闭AudioSession，清除各种标记等;
- (void)cleanUp
{
    _started   = NO;
    _isEof     = NO;
    _audioData = nil;
    _contentLength = 0;
    _buffer        = nil;
    _byteOffset    = 0;
    _dataProvider  = nil;
    _audioQueue       = nil;
    _enqueneDataQueue = nil;
    [_audioFileStream close];
    _audioFileStream = nil;
    _status          = SJAudioPlayerStatusStopped;
}


#pragma mark - methods
/**
 *  播放
 */
- (void)play
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    // 激活音频会话控制
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    
    _enqueneDataQueue = dispatch_queue_create("com.iiishijian.enqueueData", NULL);
    
    if (!_started)
    {
        [self start];
        
    }else
    {
        if (_status == SJAudioPlayerStatusPaused)
        {
            [self resume];
        }
    }
}



- (void)start
{
    _started = YES;
    
    dispatch_async(_enqueneDataQueue, ^{
    
        [self enqueneAudioData];
    });

    NSThread  *thread = [[NSThread alloc]initWithTarget:self selector:@selector(playAudioData) object:nil];
    [thread start];
}

- (void)pause
{
    _pauseRequired = YES;
}

- (void)resume
{
    _status = SJAudioPlayerStatusPlaying;
    [_audioQueue resume];
    [self mutexSignal];
}

- (void)stop
{
    _userStop = YES;
    [self mutexSignal];
}


- (void)seekToProgress:(NSTimeInterval)timeOffset
{
    _seekTime = timeOffset;
    
    @synchronized(self) {
        
        if (_isEof)
        {
            _byteOffset = [_audioFileStream seekToTime:&_seekTime];
        }else
        {
            if (_byteOffset < [_audioData length])
            {
                _byteOffset = [_audioFileStream seekToTime:&_seekTime];
            }else
            {
                _byteOffset = [_audioFileStream seekToTime:&_seekTime];
                [_buffer clean];
                [_audioQueue reset];
                _dataProvider = nil;
            }
        }
    }
}


- (void)enqueneAudioData
{
    _isEof    = NO;
    _userStop = NO;
    
    NSError *error;
    
    _audioData = [[NSMutableData alloc]init];
    
    while (!_isEof && !_userStop)
    {
        @autoreleasepool
        {
            @synchronized (self) {
            
                if (!_dataProvider)
                {
                    _dataProvider = [[SJAudioDataProvider alloc]initWithURL:[NSURL URLWithString:_urlString] cacheFilePath:_cachePath byteOffset:_byteOffset];
                }
                
                NSData *data = [_dataProvider readDataWithMaxLength:_bufferSize isEof:&_isEof];
                // 读取出错
                if (data == nil)
                {
                    break;
                }
                
                if (_isEof)
                {
                    [_dataProvider close];
                }
                
                if (_userStop)
                {
                    [_dataProvider close];
                    _dataProvider = nil;
                    NSLog(@"11111111111");
                    break;
                }
            
                if (_dataProvider.contentLength && !_audioFileStream)
                {
                    _contentLength   = _dataProvider.contentLength;
                    _audioFileStream = [[SJAudioFileStream alloc]initWithFileType:hintForFileExtension([NSURL URLWithString:_urlString].pathExtension) fileSize:_contentLength error:&error];
                    _audioFileStream.delegate = self;
                    
                    _buffer = [SJAudioBuffer buffer];
                    
                }
                
                [_audioData appendData:data];
            }
        }
    }
    
    NSLog(@"-------------------");
}


- (void)playAudioData
{
    NSError *error = nil;
    
    while (!_userStop&&_byteOffset<=_contentLength && _status != SJAudioPlayerStatusFinished) {
        
        @autoreleasepool
        {
            @synchronized (self) {

                if (_userStop)
                {
                    [_audioQueue stop:YES];
                    NSLog(@"aaaaaaaaaaaaa");
                    break;
                }
                
                if (_pauseRequired) {
                    
                    _status = SJAudioPlayerStatusPaused;
                    [_audioQueue pause];
                    [self mutexWait];
                    _pauseRequired = NO;
                }
                
                if ([_audioData length] >= _bufferSize + _byteOffset)
                {
                    if (_audioFileStream)
                    {
                        NSData *data = [_audioData subdataWithRange:NSMakeRange(_byteOffset, _bufferSize)];
                        
                        _byteOffset += data.length;
                        
                        [_audioFileStream parseData:data error:&error];
                    }
                }
                
                if (_audioQueue)
                {
                    if ([_buffer hasData])
                    {
                        UInt32 packetCount;
                        AudioStreamPacketDescription *desces = NULL;
                        
                        if ([_buffer bufferedSize] >= _bufferSize)
                        {
                            NSData *data = [_buffer dequeueDataWithSize:(UInt32)_bufferSize packetCount:&packetCount descriptions:&desces];
                            
                            [_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:_isEof];
                            
                        }else
                        {
                            NSData *data = [_buffer dequeueDataWithSize:[_buffer bufferedSize] packetCount:&packetCount descriptions:&desces];
                            
                            [_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:_isEof];
                            NSLog(@"yyyyyyyyyyy");
                        }
                        free(desces);
                        _status = SJAudioPlayerStatusPlaying;
                        
                    }else
                    {
                        NSLog(@"%u",(unsigned int)[_buffer bufferedSize]);
                        
                        [_audioQueue stop:NO];
                        _status = SJAudioPlayerStatusFinished;
                        NSLog(@"++++++++++++++++");
                    }
                }
            }
        }
    }
    
    NSLog(@"??????????????");
    
//    [self cleanUp];
}


- (void)createAudioQueue
{
    NSData *magicCookie = [_audioFileStream fetchMagicCookie];
    
    AudioStreamBasicDescription format = _audioFileStream.format;
    
    _audioQueue = [[SJAudioOutputQueue alloc]initWithFormat:format bufferSize:(UInt32)_bufferSize macgicCookie:magicCookie];
    
    if (!_audioQueue.available)
    {
        _audioQueue = nil;
    }
}


- (NSTimeInterval)duration
{
    return _audioFileStream.duration;
}

#pragma mark -delegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    @synchronized(self)
    {
        [_buffer enqueueFromDataArray:audioData];
        
        if (_isEof) {
            
            NSLog(@"eeeeeeeeeee");
        }
        
        if (!_audioQueue)
        {
            [self createAudioQueue];
        }
    }
}




/**
 *  根据 URL的pathExtension 识别音频格式
 */
AudioFileTypeID hintForFileExtension(NSString *fileExtension)
{
    AudioFileTypeID fileTypeHint = 0;
    if ([fileExtension isEqual:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
    }
    else if ([fileExtension isEqual:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
    }
    else if ([fileExtension isEqual:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
    }
    else if ([fileExtension isEqual:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
    }
    else if ([fileExtension isEqual:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
    }
    else if ([fileExtension isEqual:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
    }
    else if ([fileExtension isEqual:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
    }
    else if ([fileExtension isEqual:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    return fileTypeHint;
}

@end

