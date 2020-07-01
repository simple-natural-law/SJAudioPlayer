//
//  SJAudioPlayer.m
//  SJAudioPlayer
//
//  Created by 张诗健 on 16/12/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioPlayer.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import "SJAudioDownloader.h"
#import "SJAudioDecoder.h"
#import "SJAudioQueue.h"
#import "SJAudioCache.h"
#import <UIKit/UIApplication.h>


static UInt32 const kDefaultBufferSize = 4096; // 1024 * 4

static NSString * const SJAudioPlayerErrorDomin = @"com.audioplayer.error";


@interface SJAudioPlayer ()<SJAudioDecoderDelegate, SJAudioDownloaderDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, weak) id<SJAudioPlayerDelegate> delegate;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) SJAudioDownloader *audioDownloader;

@property (nonatomic, strong) SJAudioCache *audioCache;

@property (nonatomic, strong) SJAudioDecoder *audioDecoder;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, assign) SJAudioPlayerStatus status;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL isEof;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) BOOL finishedDownload;

@property (nonatomic, assign) BOOL stopDownload;

@property (nonatomic, assign) SInt64 byteOffset;

@property (nonatomic, assign) NSTimeInterval seekTime;

@property (nonatomic, assign) NSTimeInterval timingOffset;

@property (nonatomic, assign) NSTimeInterval duration;

@property (nonatomic, assign) NSTimeInterval progress;

@property (nonatomic, assign) unsigned long long readOffset;

// 音频数据总长度
@property (nonatomic, assign) unsigned long long contentLength;

// 已下载的数据长度（包含 实际下载的数据长度 和 偏移量）
@property (nonatomic, assign) unsigned long long didDownloadLength;

// 实际下载的数据长度
@property (nonatomic, assign) unsigned long long currentFileSize;

@property (nonatomic, assign) NSUInteger downloadRepeatCount;

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
    
    if (DEBUG)
    {
        NSLog(@"dealloc: %@",self);
    }
}


#pragma mark- Public Methods
- (instancetype)initWithUrl:(NSURL *)url delegate:(nonnull id<SJAudioPlayerDelegate>)delegate
{
    NSAssert(url, @"SJAudioPlayer: url should not be nil.");
    
    self = [super init];
    
    if (self)
    {
        self.started  = NO;
        self.url      = url;
        self.delegate = delegate;
        self.playRate = 1.0;
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}


- (void)play
{
    if (self.started)
    {
        [self resume];
    }else
    {
        [self activateAudioSession];
        
        [self start];
    }
}


- (void)pause
{
    pthread_mutex_lock(&_mutex);
    if (!self.pauseRequired)
    {
        self.pauseRequired = YES;
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)resume
{
    if (self.pausedByInterrupt && self.status == SJAudioPlayerStatusPaused)
    {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        [self.audioQueue resume];
        
        [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
        
        self.pausedByInterrupt = NO;
    }else
    {
        pthread_mutex_lock(&_mutex);
        if (self.pauseRequired && self.status != SJAudioPlayerStatusWaiting )
        {
            pthread_cond_signal(&_cond);
        }
        pthread_mutex_unlock(&_mutex);
    }
}


- (void)stop
{
    if (self.status == SJAudioPlayerStatusFinished)
    {
        return;
    }
    
    if (self.status != SJAudioPlayerStatusIdle)
    {
        pthread_mutex_lock(&_mutex);
        self.stopRequired = YES;
        if (self.pauseRequired || self.status == SJAudioPlayerStatusWaiting)
        {
            pthread_cond_signal(&_cond);
        }
        pthread_mutex_unlock(&_mutex);
        
        // 同步播放器状态切换
        while (self.status != SJAudioPlayerStatusIdle)
        {
            [NSThread sleepForTimeInterval:0.15];
        }
    }
}


- (void)seekToProgress:(NSTimeInterval)progress
{
    pthread_mutex_lock(&_mutex);
    self.seekTime = progress;
    self.seekRequired = YES;
    pthread_mutex_unlock(&_mutex);
}


- (void)setPlayRate:(float)playRate
{
    if (_playRate == playRate)
    {
        return;
    }
    
    _playRate = playRate;
    
    if (self.audioQueue)
    {
        [self.audioQueue setAudioQueuePlayRate:playRate];
    }
}


#pragma mark- Private Methods
- (void)start
{
    self.started = YES;
    
    [self updateAudioDownloadPercentageWithDataLength:0];
    
    [self setAudioPlayerStatus:SJAudioPlayerStatusWaiting];
    
    self.audioCache = [[SJAudioCache alloc] initWithURL:self.url];
    
    if ([self.audioCache isExistDiskCache])
    {
        self.contentLength = [self.audioCache getAudioDiskCacheContentLength];
        
        self.didDownloadLength = self.contentLength;
        
        [self updateAudioDownloadPercentageWithDataLength:self.didDownloadLength];
    }else
    {
        [self startDownloadAudioData];
    }
    
    [self startPlayAudioData];
}


- (void)startDownloadAudioData
{
    NSThread *downloadThread = [[NSThread alloc] initWithTarget:self selector:@selector(downloadAudioData) object:nil];
    
    [downloadThread setName:@"com.audioplayer.download"];
    
    [downloadThread start];
}


- (void)startPlayAudioData
{
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"com.audioplayer.play"];
    
    [playAudioThread start];
}


- (void)downloadAudioData
{
    self.finishedDownload = NO;
    self.stopDownload     = NO;
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:2.0];
    
    while (!self.finishedDownload && !self.stopDownload)
    {
        if (self.audioDownloader == nil)
        {
            self.audioDownloader = [SJAudioDownloader downloadAudioWithURL:self.url byteOffset:self.byteOffset delegate:self];
        }
        
        [runloop runMode:NSDefaultRunLoopMode beforeDate:date];
        
        [NSThread sleepForTimeInterval:0.02];
    }
}



- (void)playAudioData
{
    while (self.started)
    {
        @autoreleasepool
        {
            if (self.isEof)
            {
                [self.audioQueue stop:NO];
                
                break;
            }
            
            NSData *data = nil;
            
            if ([self.audioCache isExistDiskCache])
            {
                data = [self.audioCache getAudioDataWithLength:kDefaultBufferSize];
                
                pthread_mutex_lock(&_mutex);
                self.readOffset += [data length];
                if (self.readOffset >= self.contentLength)
                {
                    self.isEof = YES;
                }
                pthread_mutex_unlock(&_mutex);
                
            }else
            {
                pthread_mutex_lock(&_mutex);
                unsigned long long currentFileSize = self.currentFileSize;
                unsigned long long readOffset = self.readOffset;
                pthread_mutex_unlock(&_mutex);
                
                if (currentFileSize < (readOffset + kDefaultBufferSize))
                {
                    if (self.finishedDownload)
                    {
                        data = [self.audioCache getAudioDataWithLength:currentFileSize - readOffset];
                        
                        self.isEof = YES;
                        
                        if (currentFileSize < self.contentLength)
                        {
                            [self.audioCache removeAudioCache];
                        }
                        
                    }else
                    {
                        [self setAudioPlayerStatus:SJAudioPlayerStatusWaiting];
                        
                        pthread_mutex_lock(&_mutex);
                        pthread_cond_wait(&_cond, &_mutex);
                        pthread_mutex_unlock(&_mutex);
                    }
                }else
                {
                    data = [self.audioCache getAudioDataWithLength:kDefaultBufferSize];
                }
                
                pthread_mutex_lock(&_mutex);
                self.readOffset += [data length];
                pthread_mutex_unlock(&_mutex);
            }
            
            if (data.length)
            {
                [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
                
                if (self.audioDecoder == nil)
                {
                    self.audioDecoder = [SJAudioDecoder startDecodeAudioWithAudioType:self.url.pathExtension audioContentLength:self.contentLength delegate:self];
                    
                    if (self.audioDecoder == nil)
                    {
                        if (DEBUG)
                        {
                            NSLog(@"SJAudioDecoder: failed to open AudioFileStream.");
                        }
                    }
                }
                
                BOOL success = [self.audioDecoder parseAudioData:data];
                
                if (!success)
                {
                    [self stopAudioQueueNow];
                    
                    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:-6002 userInfo:@{NSLocalizedDescriptionKey: @"SJAudioDownloader: error parsing audio data!",NSURLErrorFailingURLErrorKey: self.url}];
                    
                    [self handleError:error];
                    
                    break;
                }
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL pauseRequired = self.pauseRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (pauseRequired)
            {
                if (self.stopRequired)
                {
                    [self stopAudioQueueNow];
                    
                    break;
                }
                
                pthread_mutex_lock(&_mutex);
                
                [self.audioQueue pause];
                
                [self setAudioPlayerStatus:SJAudioPlayerStatusPaused];
                
                pthread_cond_wait(&_cond, &_mutex);
                
                pthread_mutex_unlock(&_mutex);
                
                
                if (self.stopRequired)
                {
                    [self stopAudioQueueNow];
                    
                    break;
                    
                }else
                {
                    [self.audioQueue resume];
                    
                    pthread_mutex_lock(&_mutex);
                    self.pauseRequired = NO;
                    pthread_mutex_unlock(&_mutex);
                    
                    [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
                }
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL stopRequired = self.stopRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (stopRequired)
            {
                [self stopAudioQueueNow];
                
                break;
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL seekRequired = self.seekRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (seekRequired)
            {
                [self seek];
            }
        }
    }
    
    [self cleanUp];
}


- (void)cleanUp
{
    if (!self.finishedDownload)
    {
        [self.audioDownloader cancelDownload];
    }
    self.audioDownloader = nil;
    
    [self.audioCache closeWriteAndReadCache];
    self.audioCache = nil;
    
    [self.audioDecoder endDecode];
    self.audioDecoder = nil;
    
    [self.audioQueue disposeAudioQueue];
    self.audioQueue = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
    
    if (self.isEof)
    {
        [self setAudioPlayerStatus:SJAudioPlayerStatusFinished];
    }else
    {
        [self setAudioPlayerStatus:SJAudioPlayerStatusIdle];
    }
}


- (void)activateAudioSession
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    [audioSession setActive:YES error:nil];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterreption:) name:AVAudioSessionInterruptionNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRouteDidChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
}



- (void)stopAudioQueueNow
{
    [self.audioQueue stop:YES];
    
    self.stopDownload = YES;
    
    if (![self.audioCache isExistDiskCache])
    {
        pthread_mutex_lock(&_mutex);
        unsigned long long currentFileSize = self.currentFileSize;
        pthread_mutex_unlock(&_mutex);
        
        if (currentFileSize < self.contentLength || self.contentLength == 0)
        {
            [self.audioCache removeAudioCache];
        }
    }
}


- (void)seek
{
    SInt64 offset = [self.audioDecoder seekToTime:&_seekTime];
    
    if ([self.audioCache isExistDiskCache])
    {
        pthread_mutex_lock(&_mutex);
        self.readOffset = offset;
        pthread_mutex_unlock(&_mutex);
        
        [self.audioCache seekToOffset:offset];
    }else
    {
        if (self.finishedDownload)
        {
            if (offset < self.byteOffset)
            {
                pthread_mutex_lock(&_mutex);
                self.byteOffset = offset;
                self.readOffset = 0;
                self.currentFileSize = 0;
                self.finishedDownload = NO;
                pthread_mutex_unlock(&_mutex);
                
                [self.audioCache closeWriteAndReadCache];
                
                [self.audioCache removeAudioCache];
                
                self.audioCache = [[SJAudioCache alloc] initWithURL:self.url];
                
                self.audioDownloader = nil;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                   
                    [self startDownloadAudioData];
                });
                
            }else
            {
                pthread_mutex_lock(&_mutex);
                self.readOffset = offset - self.byteOffset;
                pthread_mutex_unlock(&_mutex);
                
                [self.audioCache seekToOffset:self.readOffset];
            }
        }else
        {
            pthread_mutex_lock(&_mutex);
            unsigned long long didDownloadLength = self.didDownloadLength;
            pthread_mutex_unlock(&_mutex);
            
            if (offset > didDownloadLength)
            {
                [self.audioDownloader cancelDownload];
                pthread_mutex_lock(&_mutex);
                self.byteOffset = offset;
                self.readOffset = 0;
                self.currentFileSize = 0;
                pthread_mutex_unlock(&_mutex);

                [self.audioCache closeWriteAndReadCache];
                
                [self.audioCache removeAudioCache];
                
                self.audioCache = [[SJAudioCache alloc] initWithURL:self.url];
                
                self.audioDownloader = nil;
            }else
            {
                if (offset < self.byteOffset)
                {
                    [self.audioDownloader cancelDownload];
                    
                    pthread_mutex_lock(&_mutex);
                    self.byteOffset = offset;
                    self.currentFileSize = 0;
                    self.readOffset = 0;
                    pthread_mutex_unlock(&_mutex);
                    
                    [self.audioCache closeWriteAndReadCache];
                    
                    [self.audioCache removeAudioCache];
                    
                    self.audioCache = [[SJAudioCache alloc] initWithURL:self.url];
                    
                    self.audioDownloader = nil;
                }else
                {
                    pthread_mutex_lock(&_mutex);
                    self.readOffset = offset - self.byteOffset;
                    pthread_mutex_unlock(&_mutex);
                    
                    [self.audioCache seekToOffset:self.readOffset];
                }
            }
        }
    }
    
    self.timingOffset = self.seekTime - self.audioQueue.playedTime;
    
    [self.audioQueue reset];
    
    pthread_mutex_lock(&_mutex);
    self.seekRequired = NO;
    pthread_mutex_unlock(&_mutex);
}



- (NSTimeInterval)progress
{
    if (self.seekRequired)
    {
        return self.seekTime;
    }
    return self.timingOffset + self.audioQueue.playedTime;
}


- (BOOL)isPlaying
{
    return (self.status == SJAudioPlayerStatusPlaying);
}



- (void)updateAudioDownloadPercentageWithDataLength:(unsigned long long)dataLength
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioPlayer:updateAudioDownloadPercentage:)])
    {
        float percentage = 0.0;
        
        if (self.contentLength > 0)
        {
            float length = dataLength;
            
            percentage = length / self.contentLength;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate audioPlayer:self updateAudioDownloadPercentage:percentage];
        });
    }
}


- (void)setAudioPlayerStatus:(SJAudioPlayerStatus)status
{
    if (self.status == status)
    {
        return;
    }
    
    self.status = status;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioPlayer:statusDidChanged:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate audioPlayer:self statusDidChanged:status];
        });
    }
}

- (void)handleError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(audioPlayer:errorOccurred:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate audioPlayer:self errorOccurred:error];
        });
    }
}



#pragma mark- SJAudioDownloaderDelegate
- (void)downloader:(SJAudioDownloader *)downloader getAudioContentLength:(unsigned long long)contentLength
{
    self.contentLength = contentLength;
}


- (void)downloader:(SJAudioDownloader *)downloader didReceiveData:(NSData *)data
{
    if (self.stopDownload)
    {
        return;
    }
    
    [self.audioCache storeAudioData:data];
    
    pthread_mutex_lock(&_mutex);
    
    self.currentFileSize += [data length];
    
    unsigned long long unreadDataLength = (self.currentFileSize - self.readOffset);
    
    self.didDownloadLength = self.currentFileSize + self.byteOffset;
    
    if (unreadDataLength >= kDefaultBufferSize)
    {
        if (self.status == SJAudioPlayerStatusWaiting)
        {
            pthread_cond_signal(&_cond);
        }
    }
    
    pthread_mutex_unlock(&_mutex);
    
    [self updateAudioDownloadPercentageWithDataLength:self.didDownloadLength];
}


- (void)downloaderDidFinished:(SJAudioDownloader *)downloader
{
    self.finishedDownload = YES;
    
    if (self.status == SJAudioPlayerStatusWaiting)
    {
        pthread_mutex_lock(&_mutex);
        pthread_cond_signal(&_cond);
        pthread_mutex_unlock(&_mutex);
    }
}


- (void)downloaderErrorOccurred:(SJAudioDownloader *)downloader
{
    [NSThread sleepForTimeInterval:1.0];
    
    self.downloadRepeatCount++;
    
    if (self.downloadRepeatCount == 4)
    {
        [self stop];
        
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:-6001 userInfo:@{NSLocalizedDescriptionKey: @"SJAudioDownloader: error downloading audio!",NSURLErrorFailingURLErrorKey: self.url}];
        
        [self handleError:error];
    }else
    {
        self.audioDownloader = [SJAudioDownloader downloadAudioWithURL:self.url byteOffset:self.byteOffset delegate:self];
    }
}


#pragma mark- SJAudioDecoderDelegate
- (void)audioDecoder:(SJAudioDecoder *)audioDecoder receiveInputData:(const void *)inputData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
{
    BOOL success = [self.audioQueue playData:[NSData dataWithBytes:inputData length:numberOfBytes] packetCount:numberOfPackets packetDescriptions:packetDescriptions isEof:self.isEof];
    
    if (!success)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioQueue: failed to play packet data.");
        }
    }
}


- (void)audioDecoder:(SJAudioDecoder *)audioDecoder readyToProducePacketsAndGetMagicCookieData:(NSData *)magicCookieData
{
    AudioStreamBasicDescription format = self.audioDecoder.format;
    
    self.audioQueue = [[SJAudioQueue alloc] initWithFormat:format bufferSize:kDefaultBufferSize macgicCookie:magicCookieData];
    
    [self.audioQueue setAudioQueuePlayRate:self.playRate];
    
    self.duration = self.audioDecoder.duration;
}




#pragma mark- AVAudioSessionInterruptionNotification
- (void)handleInterreption:(NSNotification *)notification
{
    AVAudioSessionInterruptionType interruptionType = [[[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    
    if (interruptionType == AVAudioSessionInterruptionTypeBegan)
    {
        // AudioQueue此时已经被系统暂停，这个时候AudioQueue由于没有可以复用的Buffer，会阻塞播放音频的线程。
        if (self.status == SJAudioPlayerStatusPlaying || self.status == SJAudioPlayerStatusWaiting)
        {
            self.pausedByInterrupt = YES;
            
            [self setAudioPlayerStatus:SJAudioPlayerStatusPaused];
        }
        
    }else if (interruptionType == AVAudioSessionInterruptionTypeEnded)
    {
        if (self.status == SJAudioPlayerStatusPaused && self.pausedByInterrupt)
        {
            [self.audioQueue resume];
            
            [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
            
            self.pausedByInterrupt = NO;
        }
    }
}


#pragma mark- AVAudioSessionRouteChangeNotification
- (void)audioSessionRouteDidChange:(NSNotification *)notification
{
    NSDictionary *dic = notification.userInfo;
    
    NSUInteger changeReason= [dic[AVAudioSessionRouteChangeReasonKey] integerValue];
    
    //等于AVAudioSessionRouteChangeReasonOldDeviceUnavailable表示旧输出不可用
    if (changeReason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
    {
        AVAudioSessionRouteDescription *routeDescription=dic[AVAudioSessionRouteChangePreviousRouteKey];
        
        AVAudioSessionPortDescription *portDescription= [routeDescription.outputs firstObject];
        
        //原设备为耳机则暂停
        if ([portDescription.portType isEqualToString:@"Headphones"])
        {
            [self pause];
        }
    }
}


#pragma mark- UIApplicationWillTerminateNotification
- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self stop];
}

@end

