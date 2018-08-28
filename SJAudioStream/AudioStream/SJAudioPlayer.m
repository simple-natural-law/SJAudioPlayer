//
//  SJAudioPlayer.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioPlayer.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import "SJAudioStream.h"
#import "SJAudioFileStream.h"
#import "SJAudioQueue.h"


static NSUInteger const kDefaultBufferSize = 4096;

@interface SJAudioPlayer ()<SJAudioFileStreamDelegate, SJAudioStreamDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, strong) SJAudioStream *audioStream;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) SJAudioFileStream *audioFileStream;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, assign) SInt64 byteOffset;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL isEof;

@property (nonatomic, assign) BOOL readDataFormLocalFile;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) NSTimeInterval seekTime;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, assign) unsigned long long contentLength;

@property (nonatomic, assign) SJAudioPlayerStatus status;

@property (nonatomic, assign) NSTimeInterval duration;

@property (nonatomic, assign) NSTimeInterval progress;

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithUrl:(NSURL *)url;
{
    NSAssert(url, @"url should be not nil.");
    
    self = [super init];
    
    if (self)
    {
        self.url     = url;
        self.started = NO;
        
        self.readDataFormLocalFile = [self.url isFileURL];
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}


#pragma mark - methods
- (void)play
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    // 激活音频会话控制
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    
    if (!self.started)
    {
        [self start];
    }else
    {
        [self resume];
    }
}


- (void)start
{
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"com.playAudio.thread"];
    
    [playAudioThread start];
}



- (void)playAudioData
{
    self.started = YES;
    
    NSError *openAudioFileStreamError = nil;
    NSError *parseDataError = nil;
    
    self.isEof = NO;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    
    NSUInteger didReadLength = 0;
    
    BOOL isRuning = YES;
    
    while (isRuning && self.started && self.status != SJAudioPlayerStatusFinished)
    {
        @autoreleasepool
        {
            if (self.readDataFormLocalFile)
            {
                if (!self.fileHandle)
                {
                    self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.url.path];
                    
                    self.contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.url.path error:nil] fileSize];
                }
                
                NSData *data = [self.fileHandle readDataOfLength:kDefaultBufferSize];

                didReadLength += [data length];

                if (didReadLength >= self.contentLength)
                {
                    self.isEof = YES;
                }
                
                if (data.length)
                {
                    if (!self.audioFileStream)
                    {
                        self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:hintForFileExtension(self.url.pathExtension) fileSize:self.contentLength error:&openAudioFileStreamError];
                        
                        if (openAudioFileStreamError)
                        {
                            NSLog(@"error: failed to open AudioFileStream.");
                        }
                        
                        self.audioFileStream.delegate = self;
                    }
                    
                    [self.audioFileStream parseData:data error:&parseDataError];
                    
                    if (parseDataError)
                    {
                        NSLog(@"error: failed to parse audio data.");
                    }
                }
            }else
            {
                if (!self.audioStream)
                {
                    self.audioStream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.byteOffset delegate:self];
                }
                
                isRuning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            }
            
            if (self.isEof)
            {
                [self.audioQueue stop:NO];
                
                self.status = SJAudioPlayerStatusFinished;
                
                NSLog(@"play audio: complete");
            }
        }
    }
    
    [self cleanUp];
}


- (void)cleanUp
{
    self.started    = NO;
    self.byteOffset = 0;
    self.status     = SJAudioPlayerStatusIdle;
    self.audioQueue = nil;
    
    [self.fileHandle closeFile];
    self.fileHandle = nil;
    
    [self.audioStream closeReadStream];
    self.audioStream = nil;
    
    [self.audioFileStream close];
    self.audioFileStream = nil;
    
    self.contentLength = 0;
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
    pthread_mutex_lock(&_mutex);
    if (self.pauseRequired)
    {
        pthread_cond_signal(&_cond);
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)stop
{
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
}


- (void)seekToProgress:(NSTimeInterval)progress
{
    self.seekTime = progress;
    
    if (self.isEof)
    {
        self.byteOffset = [self.audioFileStream seekToTime:&_seekTime];
    }else
    {
        self.byteOffset = [self.audioFileStream seekToTime:&_seekTime];
        [self.audioQueue reset];
        [self.audioStream closeReadStream];
        self.audioStream = nil;
    }
}

- (NSTimeInterval)progress
{
    return self.audioQueue.playedTime;
}


- (void)createAudioQueue
{
    NSData *magicCookie = [self.audioFileStream getMagicCookieData];
    
    AudioStreamBasicDescription format = self.audioFileStream.format;
    
    self.audioQueue = [[SJAudioQueue alloc] initWithFormat:format bufferSize:(UInt32)kDefaultBufferSize macgicCookie:magicCookie];
}

#pragma mark- SJAudioStreamDelegate
- (void)audioReadStreamHasBytesAvailable:(SJAudioStream *)audioStream
{
    NSError *readDataError = nil;
    NSError *openAudioFileStreamError = nil;
    NSError *parseDataError = nil;

    NSData *data = [self.audioStream readDataWithMaxLength:kDefaultBufferSize error:&readDataError];

    if (readDataError)
    {
        NSLog(@"error: failed to read data.");
    }

    if (data.length)
    {
        if (!self.audioFileStream)
        {
            self.contentLength = self.audioStream.contentLength;

            self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:hintForFileExtension(self.url.pathExtension) fileSize:self.contentLength error:&openAudioFileStreamError];

            if (openAudioFileStreamError)
            {
                NSLog(@"error: failed to open AudioFileStream.");
            }

            self.audioFileStream.delegate = self;
        }

        [self.audioFileStream parseData:data error:&parseDataError];

        if (parseDataError)
        {
            NSLog(@"error: failed to parse audio data.");
        }
    }
}

- (void)audioReadStreamEndEncountered:(SJAudioStream *)audioStream
{
    self.isEof = YES;
}

- (void)audioReadStreamErrorOccurred:(SJAudioStream *)audioStream
{
    
}


#pragma mark- SJAudioFileStreamDelegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream receiveInputData:(const void *)inputData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
{
    pthread_mutex_lock(&_mutex);
    
    if (self.pauseRequired)
    {
        NSLog(@"play audio: pause");
        
        [self.audioQueue pause];
        
        self.status = SJAudioPlayerStatusPaused;
        
        pthread_cond_wait(&_cond, &_mutex); // 阻塞
        
        if (!self.stopRequired)
        {
            [self.audioQueue resume];
            
            self.pauseRequired = NO;
            
            self.status = SJAudioPlayerStatusPlaying;
            
            NSLog(@"play audio: play");
        }
    }
    pthread_mutex_unlock(&_mutex);
    
    [self.audioQueue playData:[NSData dataWithBytes:inputData length:numberOfBytes] packetCount:numberOfPackets packetDescriptions:packetDescriptions isEof:self.isEof];
}


- (void)audioFileStreamReadyToProducePackets:(SJAudioFileStream *)audioFileStream
{
    self.duration = self.audioFileStream.duration;
    
    [self createAudioQueue];
    
    self.status = SJAudioPlayerStatusWaiting;
}

/// 根据 URL的 pathExtension 识别音频格式
AudioFileTypeID hintForFileExtension (NSString *fileExtension)
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

@end

