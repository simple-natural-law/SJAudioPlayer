//
//  ZZAudioPlayer.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/22.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import "ZZAudioPlayer.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import "SJAudioDownloader.h"
#import "SJAudioDecoder.h"
#import "SJAudioQueue.h"
#import "SJAudioCache.h"


static UInt32 const kDefaultBufferSize = 4096; // 1024 * 4

static NSString *applicationWillTerminateNotification = @"UIApplicationWillTerminateNotification";

@interface ZZAudioPlayer ()<SJAudioDecoderDelegate, SJAudioDownloaderDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, weak) id<ZZAudioPlayerDelegate> delegate;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) SJAudioDownloader *audioDownloader;

@property (nonatomic, strong) SJAudioCache *audioCache;

@property (nonatomic, strong) SJAudioDecoder *audioDecoder;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, assign) ZZAudioPlayerStatus status;

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

@property (nonatomic, assign) float playRate;

@end



@implementation ZZAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
    
    if (DEBUG)
    {
        NSLog(@"dealloc: %@",self);
    }
}



- (instancetype)initWithUrl:(NSURL *)url delegate:(nonnull id<ZZAudioPlayerDelegate>)delegate
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


- (void)activateAudioSession
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    NSError *error = nil;
    
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    if (error)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioPlayer: error setting audio session category! %@",error);
        }
    }else
    {
        [audioSession setActive:YES error:&error];
        
        if (error)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioPlayer: error setting audio session active! %@", error);
            }
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterreption:) name:AVAudioSessionInterruptionNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRouteDidChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:applicationWillTerminateNotification object:nil];
}



#pragma mark- Public Methods
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
    if (self.pausedByInterrupt && self.status == ZZAudioPlayerStatusPaused)
    {
        NSError *error = nil;
        
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        
        if (error)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioPlayer: Error setting audio session active! %@", error);
            }
        }
        
        [self.audioQueue resume];
        
        [self setAudioPlayerStatus:ZZAudioPlayerStatusPlaying];
        
        self.pausedByInterrupt = NO;
    }else
    {
        pthread_mutex_lock(&_mutex);
        if (self.pauseRequired && self.status != ZZAudioPlayerStatusWaiting )
        {
            pthread_cond_signal(&_cond);
        }
        pthread_mutex_unlock(&_mutex);
    }
}


- (void)stop
{
    if (self.status != ZZAudioPlayerStatusIdle)
    {
        pthread_mutex_lock(&_mutex);
        self.stopRequired = YES;
        if (self.pauseRequired)
        {
            pthread_cond_signal(&_cond);
        }
        pthread_mutex_unlock(&_mutex);
        
        // 同步播放器状态切换
        while (self.status != ZZAudioPlayerStatusIdle)
        {
            [NSThread sleepForTimeInterval:0.05];
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


- (void)setAudioPlayRate:(float)playRate
{
    self.playRate = playRate;
    
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
    
    [self setAudioPlayerStatus:ZZAudioPlayerStatusWaiting];
    
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
    
    [self startPlayAudio];
}


- (void)startDownloadAudioData
{
    NSThread *downloadThread = [[NSThread alloc] initWithTarget:self selector:@selector(downloadAudioData) object:nil];
    
    [downloadThread setName:@"com.audioplayer.download"];
    
    [downloadThread start];
}


- (void)startPlayAudio
{
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudio) object:nil];
    
    [playAudioThread setName:@"com.audioplayer.play"];
    
    [playAudioThread start];
}


- (void)downloadAudioData
{
    self.finishedDownload = NO;
    self.stopDownload     = NO;
    
    BOOL done = YES;
    
    while (done && !self.finishedDownload && !self.stopDownload)
    {
        if (self.audioDownloader == nil)
        {
            self.audioDownloader = [SJAudioDownloader downloadAudioWithURL:self.url byteOffset:self.byteOffset delegate:self];
        }
        
        done = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    }
}



- (void)playAudio
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
                        [self setAudioPlayerStatus:ZZAudioPlayerStatusWaiting];
                        
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
                [self setAudioPlayerStatus:ZZAudioPlayerStatusPlaying];
                
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
                    self.started = NO;
                    
                    [self setAudioPlayerStatus:ZZAudioPlayerStatusError];
                    
                    if (DEBUG)
                    {
                        NSLog(@"SJAudioDecoder: failed to parse audio data.");
                    }
                }
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL pauseRequired = self.pauseRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (pauseRequired)
            {
                [self.audioQueue pause];
                
                [self setAudioPlayerStatus:ZZAudioPlayerStatusPaused];
                
                pthread_mutex_lock(&_mutex);
                pthread_cond_wait(&_cond, &_mutex);
                pthread_mutex_unlock(&_mutex);
                
                pthread_mutex_lock(&_mutex);
                BOOL stopRequired = self.stopRequired;
                pthread_mutex_unlock(&_mutex);
                
                if (stopRequired)
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
                    
                    break;
                    
                }else
                {
                    [self.audioQueue resume];
                    
                    pthread_mutex_lock(&_mutex);
                    self.pauseRequired = NO;
                    pthread_mutex_unlock(&_mutex);
                    
                    [self setAudioPlayerStatus:ZZAudioPlayerStatusPlaying];
                }
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL stopRequired = self.stopRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (stopRequired)
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
                
                break;
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL seekRequired = self.seekRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (seekRequired)
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
                            [self.audioDownloader cancel];
                            self.audioDownloader = nil;
                            self.byteOffset = offset;
                            self.readOffset = 0;
                            self.currentFileSize = 0;
                            self.finishedDownload = NO;
                            pthread_mutex_unlock(&_mutex);
                            
                            [self.audioCache removeAudioCache];
                            
                            [self startDownloadAudioData];
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
                            pthread_mutex_lock(&_mutex);
                            [self.audioDownloader cancel];
                            self.audioDownloader = nil;
                            self.byteOffset = offset;
                            self.readOffset = 0;
                            self.currentFileSize = 0;
                            pthread_mutex_unlock(&_mutex);
                            
                            [self.audioCache removeAudioCache];
                        }else
                        {
                            if (offset < self.byteOffset)
                            {
                                pthread_mutex_lock(&_mutex);
                                [self.audioDownloader cancel];
                                self.audioDownloader = nil;
                                self.byteOffset = offset;
                                self.readOffset = 0;
                                self.currentFileSize = 0;
                                pthread_mutex_unlock(&_mutex);
                                
                                [self.audioCache removeAudioCache];
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
        }
    }
    
    if (self.isEof)
    {
        [self setAudioPlayerStatus:ZZAudioPlayerStatusFinished];
    }
    
    [self cleanUp];
}


- (void)cleanUp
{
    self.started       = NO;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    self.seekRequired  = NO;
    self.pausedByInterrupt = NO;
    
    [self.audioQueue disposeAudioQueue];
    self.audioQueue = nil;
    
    [self.audioCache closeWriteAndReadCache];
    self.audioCache = nil;
    
    [self.audioDownloader cancel];
    self.audioDownloader = nil;
    
    [self.audioDecoder endDecode];
    self.audioDecoder = nil;
    
    self.byteOffset        = 0;
    self.duration          = 0.0;
    self.timingOffset      = 0.0;
    self.seekTime          = 0.0;
    self.contentLength     = 0;
    self.didDownloadLength = 0;
    self.readOffset        = 0;
    self.currentFileSize   = 0;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:applicationWillTerminateNotification object:nil];
    
    [self setAudioPlayerStatus:ZZAudioPlayerStatusIdle];
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
    return (self.status == ZZAudioPlayerStatusPlaying);
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


- (void)setAudioPlayerStatus:(ZZAudioPlayerStatus)status
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
        if (self.status == ZZAudioPlayerStatusWaiting)
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
}


- (void)downloaderErrorOccurred:(SJAudioDownloader *)downloader
{
    [NSThread sleepForTimeInterval:1.0];
    
    self.audioDownloader = [SJAudioDownloader downloadAudioWithURL:self.url byteOffset:self.currentFileSize delegate:self];
    
    if (DEBUG)
    {
        NSLog(@"SJAudioStream: error occurred.");
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
        if (self.status == ZZAudioPlayerStatusPlaying || self.status == ZZAudioPlayerStatusWaiting)
        {
            self.pausedByInterrupt = YES;
            
            [self setAudioPlayerStatus:ZZAudioPlayerStatusPaused];
        }
        
    }else if (interruptionType == AVAudioSessionInterruptionTypeEnded)
    {
        if (self.status == ZZAudioPlayerStatusPaused && self.pausedByInterrupt)
        {
            [self.audioQueue resume];
            
            [self setAudioPlayerStatus:ZZAudioPlayerStatusPlaying];
            
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
