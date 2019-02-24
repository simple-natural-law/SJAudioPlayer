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
#import "SJAudioStream.h"
#import "SJAudioFileStream.h"
#import "SJAudioQueue.h"
#import <CommonCrypto/CommonDigest.h>


static UInt32 const kDefaultBufferSize = 4096;

@interface SJAudioPlayer ()<SJAudioFileStreamDelegate, SJAudioStreamDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, weak) id<SJAudioPlayerDelegate> delegate;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) SJAudioStream *audioStream;

@property (nonatomic, strong) NSFileHandle *readFileHandle;

@property (nonatomic, strong) NSFileHandle *writeFileHandle;

@property (nonatomic, strong) NSString *cachePath;

@property (nonatomic, strong) SJAudioFileStream *audioFileStream;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, assign) SJAudioPlayerStatus status;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL isEof;

@property (nonatomic, assign) BOOL readDataFormLocalFile;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) BOOL finishedDownload;

@property (nonatomic, assign) BOOL stopReadHTTPData;

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

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithUrl:(NSURL *)url delegate:(nonnull id<SJAudioPlayerDelegate>)delegate
{
    NSAssert(url, @"SJAudioPlayer: url should be not nil.");
    
    self = [super init];
    
    if (self)
    {
        self.started  = NO;
        self.url      = url;
        self.delegate = delegate;
        
        if ([self.url isFileURL])
        {
            self.readDataFormLocalFile = YES;
        }else
        {
            NSString *filePath = [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"Audio"] stringByAppendingPathComponent:[self getMD5StringForString:url.absoluteString]];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:filePath])
            {
                self.readDataFormLocalFile = YES;
                
                self.cachePath = filePath;
                
            }else
            {
                self.readDataFormLocalFile = NO;
            }
        }
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}


#pragma mark- Public Methods
- (void)play
{
    if (self.started)
    {
        [self resume];
    }else
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
            // 激活音频会话控制
            [audioSession setActive:YES error:&error];
            
            if (error)
            {
                if (DEBUG)
                {
                    NSLog(@"SJAudioPlayer: error setting audio session active! %@", error);
                }
            }
        }
        
        // 监听打断事件
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterreption:) name:AVAudioSessionInterruptionNotification object:nil];
        
        // 监听拔出耳机操作
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRouteDidChange:) name:AVAudioSessionRouteChangeNotification object:nil];
        
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
    if (!self.stopRequired)
    {
        [self setAudioPlayerStatus:SJAudioPlayerStatusIdle];
    }
    
    pthread_mutex_lock(&_mutex);
    if (!self.stopRequired)
    {
        self.stopRequired = YES;
        
        if (self.pauseRequired)
        {
            pthread_cond_signal(&_cond);
        }
    }
    pthread_mutex_unlock(&_mutex);
    
    [NSThread sleepForTimeInterval:0.1];
}


- (void)seekToProgress:(NSTimeInterval)progress
{
    self.seekTime = progress;
    
    self.seekRequired = YES;
}



#pragma mark- Private Methods
- (void)start
{
    self.started = YES;
    
    [self updateAudioDownloadPercentageWithDataLength:0];
    
    if (self.readDataFormLocalFile)
    {
        NSError *error = nil;
        
        if ([self.url isFileURL])
        {
            self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:self.url.path];
            
            self.contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.url.path error:&error] fileSize];
        }else
        {
            self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:self.cachePath];
            
            self.contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.cachePath error:&error] fileSize];
        }
        
        if (error)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioPlayer: failed to get attributes of the audio file.");
            }
        }
        
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
    
    [downloadThread setName:@"com.downloadData.thread"];
    
    [downloadThread start];
}


- (void)startPlayAudioData
{
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"com.playAudio.thread"];
    
    [playAudioThread start];
}


- (void)downloadAudioData
{
    self.finishedDownload = NO;
    self.stopReadHTTPData = NO;
    
    BOOL done = YES;
    
    while (done && !self.finishedDownload && !self.stopReadHTTPData)
    {
        if (!self.audioStream)
        {
            self.audioStream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.byteOffset delegate:self];
        }
        
        done = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        
        // 避免读取音频数据的频率太快而导致CPU消耗过高
        [NSThread sleepForTimeInterval:0.01];
    }
}

- (void)playAudioData
{
    NSError *openAudioFileStreamError = nil;
    NSError *parseDataError = nil;
    
    self.isEof = NO;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    
    while (self.started)
    {
        @autoreleasepool
        {
            if (self.isEof)
            {
                [self.audioQueue stop:NO];
                
                self.started = NO;
                
                break;
            }
            
            pthread_mutex_lock(&_mutex);
            BOOL pauseRequired = self.pauseRequired;
            pthread_mutex_unlock(&_mutex);
            
            if (pauseRequired)
            {
                [self.audioQueue pause];
                
                [self setAudioPlayerStatus:SJAudioPlayerStatusPaused];
                
                pthread_mutex_lock(&_mutex);
                pthread_cond_wait(&_cond, &_mutex);
                pthread_mutex_unlock(&_mutex);
                
                if (self.stopRequired)
                {
                    [self.audioQueue stop:YES];
                    
                    self.stopReadHTTPData = YES;
                    
                    self.started = NO;
                    
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
            
            if (self.stopRequired)
            {
                [self.audioQueue stop:YES];
                
                self.stopReadHTTPData = YES;
                
                self.started = NO;
                
                [self.readFileHandle closeFile];
                
                if (!self.readDataFormLocalFile)
                {
                    pthread_mutex_lock(&_mutex);
                    unsigned long long currentFileSize = self.currentFileSize;
                    pthread_mutex_unlock(&_mutex);
                    
                    if (currentFileSize < self.contentLength)
                    {
                        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
                        
                        if (!success)
                        {
                            if (DEBUG)
                            {
                                NSLog(@"SJAudioPlayer: failed to remove file.");
                            }
                        }
                    }
                }
                
                break;
            }
            
            if (self.seekRequired)
            {
                NSUInteger offset = [self.audioFileStream seekToTime:&_seekTime];
                
                if (self.readDataFormLocalFile)
                {
                    pthread_mutex_lock(&_mutex);
                    self.readOffset = offset;
                    pthread_mutex_unlock(&_mutex);
                    
                    [self.readFileHandle seekToFileOffset:offset];
                }else
                {
                    if (self.finishedDownload)
                    {
                        if (offset < self.byteOffset)
                        {
                            pthread_mutex_lock(&_mutex);
                            [self.audioStream closeReadStream];
                            self.audioStream = nil;
                            self.byteOffset = offset;
                            pthread_mutex_unlock(&_mutex);
                            
                            BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
                            
                            if (!success)
                            {
                                if (DEBUG)
                                {
                                    NSLog(@"SJAudioPlayer: failed to remove file.");
                                }
                            }
                            
                            self.readOffset = 0;
                            self.currentFileSize = 0;
                            
                            [self.writeFileHandle closeFile];
                            [self.readFileHandle closeFile];
                            self.writeFileHandle = nil;
                            self.readFileHandle = nil;
                        }else
                        {
                            pthread_mutex_lock(&_mutex);
                            self.readOffset = offset - self.byteOffset;
                            pthread_mutex_unlock(&_mutex);
                            
                            [self.readFileHandle seekToFileOffset:self.readOffset];
                        }
                    }else
                    {
                        pthread_mutex_lock(&_mutex);
                        unsigned long long didDownloadLength = self.didDownloadLength;
                        pthread_mutex_unlock(&_mutex);
                        
                        if (offset > didDownloadLength)
                        {
                            pthread_mutex_lock(&_mutex);
                            [self.audioStream closeReadStream];
                            self.audioStream = nil;
                            self.byteOffset = offset;
                            pthread_mutex_unlock(&_mutex);
                            
                            BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
                            
                            if (!success)
                            {
                                if (DEBUG)
                                {
                                    NSLog(@"SJAudioPlayer: failed to remove file.");
                                }
                            }
                            
                            self.readOffset = 0;
                            self.currentFileSize = 0;
                            
                            [self.writeFileHandle closeFile];
                            [self.readFileHandle closeFile];
                            self.writeFileHandle = nil;
                            self.readFileHandle = nil;
                        }else
                        {
                            if (offset < self.byteOffset)
                            {
                                pthread_mutex_lock(&_mutex);
                                [self.audioStream closeReadStream];
                                self.audioStream = nil;
                                self.byteOffset = offset;
                                pthread_mutex_unlock(&_mutex);
                                
                                BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
                                
                                if (!success)
                                {
                                    if (DEBUG)
                                    {
                                        NSLog(@"SJAudioPlayer: failed to remove file.");
                                    }
                                }
                                
                                self.readOffset = 0;
                                self.currentFileSize = 0;
                                
                                [self.writeFileHandle closeFile];
                                [self.readFileHandle closeFile];
                                self.writeFileHandle = nil;
                                self.readFileHandle = nil;
                            }else
                            {
                                pthread_mutex_lock(&_mutex);
                                self.readOffset = offset - self.byteOffset;
                                pthread_mutex_unlock(&_mutex);
                                
                                [self.readFileHandle seekToFileOffset:self.readOffset];
                            }
                        }
                    }
                }
                
                self.timingOffset = self.seekTime - self.audioQueue.playedTime;
                
                [self.audioQueue reset];
                
                self.seekRequired = NO;
            }
            
            
            NSData *data = nil;
            
            if (self.readDataFormLocalFile)
            {
                data = [self.readFileHandle readDataOfLength:kDefaultBufferSize];
                
                pthread_mutex_lock(&_mutex);
                self.readOffset += [data length];
                pthread_mutex_unlock(&_mutex);
                
                if (self.readOffset >= self.contentLength)
                {
                    self.isEof = YES;
                    
                    [self.readFileHandle closeFile];
                }
                
            }else
            {
                pthread_mutex_lock(&_mutex);
                unsigned long long currentFileSize = self.currentFileSize;
                pthread_mutex_unlock(&_mutex);
                
                if (currentFileSize < (self.readOffset + kDefaultBufferSize))
                {
                    if (self.finishedDownload)
                    {
                        data = [self.readFileHandle readDataOfLength:currentFileSize - self.readOffset];
                        
                        self.isEof = YES;
                        
                        [self.readFileHandle closeFile];
                        
                        if (currentFileSize < self.contentLength)
                        {
                            BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
                            
                            if (!success)
                            {
                                if (DEBUG)
                                {
                                    NSLog(@"SJAudioPlayer: failed to remove file.");
                                }
                            }
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
                    data = [self.readFileHandle readDataOfLength:kDefaultBufferSize];
                }
                
                pthread_mutex_lock(&_mutex);
                self.readOffset += [data length];
                pthread_mutex_unlock(&_mutex);
            }
            
            [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
            
            if (data.length)
            {
                if (!self.audioFileStream)
                {
                    if (!self.readDataFormLocalFile)
                    {
                        self.contentLength = self.audioStream.contentLength;
                    }
                    
                    self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:[self getAudioFileTypeIdForFileExtension:self.url.pathExtension] fileSize:self.contentLength error:&openAudioFileStreamError];
                    
                    if (openAudioFileStreamError)
                    {
                        if (DEBUG)
                        {
                            NSLog(@"SJAudioFileStream: failed to open AudioFileStream.");
                        }
                    }
                    
                    self.audioFileStream.delegate = self;
                }
                
                [self.audioFileStream parseData:data error:&parseDataError];
                
                if (parseDataError)
                {
                    if (DEBUG)
                    {
                        NSLog(@"SJAudioFileStream: failed to parse audio data.");
                    }
                }
            }
        }
    }
    
    if (self.isEof)
    {
        [self setAudioPlayerStatus:SJAudioPlayerStatusFinished];
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
    
    [self.readFileHandle closeFile];
    self.readFileHandle = nil;
    
    [self.audioStream closeReadStream];
    self.audioStream = nil;
    
    [self.audioFileStream close];
    self.audioFileStream = nil;
    
    self.byteOffset        = 0;
    self.duration          = 0.0;
    self.timingOffset      = 0.0;
    self.seekTime          = 0.0;
    self.contentLength     = 0;
    self.didDownloadLength = 0;
    self.readOffset        = 0;
    self.currentFileSize   = 0;
    self.cachePath         = nil;
    
    [self.writeFileHandle closeFile];
    self.writeFileHandle = nil;
    [self.readFileHandle closeFile];
    self.readFileHandle  = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
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


- (AudioFileTypeID)getAudioFileTypeIdForFileExtension:(NSString *)fileExtension
{
    AudioFileTypeID fileTypeHint = 0;
    
    if ([fileExtension isEqualToString:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
        
    }else if ([fileExtension isEqualToString:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
        
    }else if ([fileExtension isEqualToString:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
        
    }else if ([fileExtension isEqualToString:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
        
    }else if ([fileExtension isEqualToString:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
        
    }else if ([fileExtension isEqualToString:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
        
    }else if ([fileExtension isEqualToString:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
        
    }else if ([fileExtension isEqualToString:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    
    return fileTypeHint;
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


#pragma mark- SJAudioStreamDelegate
- (void)audioStreamHasBytesAvailable:(SJAudioStream *)audioStream
{
    NSError *readDataError = nil;
    
    // 每次读取 20KB 的数据（长度太小，`audioStreamHasBytesAvailable`方法调用次数太频繁，会导致CPU占用率过高）
    pthread_mutex_lock(&_mutex);
    NSData *data = [self.audioStream readDataWithMaxLength:(kDefaultBufferSize * 5) error:&readDataError];
    pthread_mutex_unlock(&_mutex);
    
    if (readDataError)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioStream: failed to read data.");
        }
    }
    
    if (self.writeFileHandle == nil)
    {
        NSString *directryPath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"Audio"];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:directryPath])
        {
            BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:directryPath withIntermediateDirectories:YES attributes:nil error:nil];
            
            if (!success)
            {
                if (DEBUG)
                {
                    NSLog(@"SJAudioStream: failed to create directry.");
                }
            }
        }
        
        NSString *filePath = [directryPath stringByAppendingPathComponent:[self getMD5StringForString:self.url.absoluteString]];
        
        BOOL success = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        
        if (!success)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioStream: failed to create file.");
            }
        }
        
        self.cachePath = filePath;
        
        self.writeFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        
        self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    }
    
    [self.writeFileHandle seekToEndOfFile];
    
    [self.writeFileHandle writeData:data];
    
    pthread_mutex_lock(&_mutex);
    self.currentFileSize += [data length];
    unsigned long long unreadDataLength = (self.currentFileSize - self.readOffset);
    pthread_mutex_unlock(&_mutex);
    
    self.didDownloadLength = self.currentFileSize + self.byteOffset;
    
    if (unreadDataLength >= kDefaultBufferSize)
    {
        if (self.status == SJAudioPlayerStatusWaiting)
        {
            pthread_mutex_lock(&_mutex);
            pthread_cond_signal(&_cond);
            pthread_mutex_unlock(&_mutex);
        }
    }
    
    [self updateAudioDownloadPercentageWithDataLength:self.didDownloadLength];
}

- (void)audioStreamEndEncountered:(SJAudioStream *)audioStream
{
    self.finishedDownload = YES;
    
    [self.writeFileHandle closeFile];
}

- (void)audioStreamErrorOccurred:(SJAudioStream *)audioStream
{
    [self.audioStream closeReadStream];
    
    [NSThread sleepForTimeInterval:1.0];
    
    self.audioStream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.currentFileSize delegate:self];;
    
    if (DEBUG)
    {
        NSLog(@"SJAudioStream: error occurred.");
    }
}

#pragma mark- SJAudioFileStreamDelegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream receiveInputData:(const void *)inputData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
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


- (void)audioFileStreamReadyToProducePackets:(SJAudioFileStream *)audioFileStream
{
    NSData *magicCookie = [self.audioFileStream getMagicCookieData];
    
    AudioStreamBasicDescription format = self.audioFileStream.format;
    
    self.audioQueue = [[SJAudioQueue alloc] initWithFormat:format bufferSize:kDefaultBufferSize macgicCookie:magicCookie];
    
    self.duration = self.audioFileStream.duration;
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

#pragma mark- MD5
- (NSString *)getMD5StringForString:(NSString *) str
{
    const char *cStr = [str UTF8String];
    
    unsigned char result[16];
    
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result);
    
    NSString *md5String = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",result[0], result[1], result[2], result[3],result[4], result[5], result[6], result[7],result[8], result[9], result[10], result[11],result[12], result[13], result[14], result[15]];
    
    return md5String;
}

@end
