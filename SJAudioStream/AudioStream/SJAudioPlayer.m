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
#import "SJAudioPacketData.h"
#import "SJAudioPacketsBuffer.h"


static NSUInteger const kDefaultBufferSize = 1024;

@interface SJAudioPlayer ()<SJAudioFileStreamDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, strong) SJAudioStream *audioStream;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) SJAudioFileStream *audioFileStream;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, strong) SJAudioPacketsBuffer *buffer;

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL isEof;

@property (nonatomic, assign) BOOL readDataFormLocalFile;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL stopReadDataRequired;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) NSTimeInterval seekTime;

@property (nonatomic, readwrite, strong) NSURL *url;

@property (nonatomic, readwrite, assign) NSUInteger contentLength;

@property (nonatomic, readwrite, assign) SJAudioPlayerStatus status;

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
    self.started = YES;
    
    if (self.readDataFormLocalFile)
    {
        self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.url.path];
        
        self.contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.url.path error:nil] fileSize];
    }else
    {
        self.audioStream = [[SJAudioStream alloc] initWithURL:_url byteOffset:_byteOffset];
    }
    
    NSThread  *readDataThread = [[NSThread alloc] initWithTarget:self selector:@selector(readAudioData) object:nil];
    
    [readDataThread setName:@"ReadDataThread"];
    
    [readDataThread start];
    
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"PlayAudioThread"];
    
    [playAudioThread start];
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
        self.stopReadDataRequired = YES;
        
        if (self.pauseRequired)
        {
            pthread_cond_signal(&_cond);
        }
    }
    
    pthread_mutex_unlock(&_mutex);
}


- (void)seekToProgress:(NSTimeInterval)timeOffset
{
    self.seekTime = timeOffset;
    
    if (self.isEof)
    {
        self.byteOffset = [self.audioFileStream seekToTime:&_seekTime];
    }else
    {
        if (self.byteOffset < [self.buffer bufferedSize])
        {
            self.byteOffset = [self.audioFileStream seekToTime:&_seekTime];
        }else
        {
            self.byteOffset = [self.audioFileStream seekToTime:&_seekTime];
            [self.buffer clean];
            [self.audioQueue reset];
            [self.audioStream closeReadStream];
            self.audioStream = nil;
        }
    }
}

- (void)cleanUpReadAudioDataThread
{
    [self.fileHandle closeFile];
    self.fileHandle = nil;
    
    [self.audioStream closeReadStream];
    self.audioStream = nil;
    
    [self.audioFileStream close];
    self.audioFileStream = nil;
    
    self.contentLength = 0;
}

- (void)cleanUpPlayAudioDataThread
{
    self.started    = NO;
    self.buffer     = nil;
    self.audioQueue = nil;
    self.byteOffset = 0;
    self.status     = SJAudioPlayerStatusIdle;
}


- (void)readAudioData
{
    self.isEof = NO;
    self.stopReadDataRequired = NO;
    
    NSUInteger didReadLength = 0;
    
    NSError *readDataError = nil;
    NSError *openAudioFileStreamError = nil;
    NSError *parseDataError = nil;
    
    while (!self.isEof && !self.stopReadDataRequired)
    {
        @autoreleasepool
        {
            NSData *data = nil;
            
            if (self.readDataFormLocalFile)
            {
                data = [self.fileHandle readDataOfLength:kDefaultBufferSize];
                
                didReadLength += [data length];
                
                if (didReadLength >= self.contentLength)
                {
                    self.isEof = YES;
                }
            }else
            {
                data = [self.audioStream readDataWithMaxLength:kDefaultBufferSize error:&readDataError isEof:&_isEof];
                
                if (readDataError)
                {
                    NSLog(@"error: failed to read data.");
                    
                    break;
                }
            }
            
            if (data.length)
            {
                if (!self.audioFileStream)
                {
                    if (!self.readDataFormLocalFile)
                    {
                        self.contentLength = self.audioStream.contentLength;
                    }
                    
                    self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:hintForFileExtension(self.url.pathExtension) fileSize:self.contentLength error:&openAudioFileStreamError];
                    
                    if (openAudioFileStreamError)
                    {
                        NSLog(@"error: failed to open AudioFileStream.");
                    }
                    
                    self.audioFileStream.delegate = self;
                    
                    self.buffer = [SJAudioPacketsBuffer buffer];
                }
                
                if (self.audioFileStream)
                {
                    [self.audioFileStream parseData:data error:&parseDataError];
                    
                    if (parseDataError)
                    {
                        NSLog(@"error: failed to parse audio data.");
                    }
                }
            }
        }
    }

    if (self.stopReadDataRequired)
    {
        NSLog(@"read data: stop");
    }
    
    if (self.isEof)
    {
        NSLog(@"read data: completed");
    }
    
    [self cleanUpReadAudioDataThread];
}


- (void)playAudioData
{
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    
    while (!self.stopRequired && self.status != SJAudioPlayerStatusFinished) {
        
        @autoreleasepool
        {
            if (self.audioQueue)
            {
                if ([self.buffer hasData])
                {
                    UInt32 packetCount;

                    AudioStreamPacketDescription *desces = NULL;
                    
                    if ([self.buffer bufferedSize] >= kDefaultBufferSize)
                    {
                        NSData *data = [self.buffer dequeueDataWithSize:(UInt32)kDefaultBufferSize packetCount:&packetCount descriptions:&desces];
                        
                        [self.audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:self.isEof];
                        
                    }else
                    {
                        NSData *data = [self.buffer dequeueDataWithSize:[self.buffer bufferedSize] packetCount:&packetCount descriptions:&desces];

                        [self.audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:self.isEof];
                    }
                    
                    free(desces);
                }else
                {
                    NSLog(@"%u",(unsigned int)[self.buffer bufferedSize]);
                    
                    [self.audioQueue stop:NO];
                    
                    self.status = SJAudioPlayerStatusFinished;
                    
                    NSLog(@"play audio: complete");
                }
            }else
            {
                if ([self.buffer hasData])
                {
                    [self createAudioQueue];
                    
                    self.status = SJAudioPlayerStatusPlaying;
                }
            }
            
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
        }
    }
    
    if (self.stopRequired)
    {
        [self.audioQueue stop:YES];
        
        NSLog(@"play audio: stop");
    }
    
    [self cleanUpPlayAudioDataThread];
}


- (void)createAudioQueue
{
    NSData *magicCookie = [self.audioFileStream getMagicCookieData];
    
    AudioStreamBasicDescription format = self.audioFileStream.format;
    
    self.audioQueue = [[SJAudioQueue alloc] initWithFormat:format bufferSize:(UInt32)kDefaultBufferSize macgicCookie:magicCookie];
    
    if (!self.audioQueue.available)
    {
        self.audioQueue = nil;
    }
}

- (NSTimeInterval)duration
{
    return self.audioFileStream.duration;;
}


- (NSTimeInterval)playedTime
{
    if (self.audioQueue)
    {
        return self.audioQueue.playedTime;
    }else
    {
        return 0.0;
    }
}


#pragma mark- SJAudioFileStreamDelegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream receiveAudioPacketData:(SJAudioPacketData *)audioPacketData
{
    [self.buffer enqueueData:audioPacketData];
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

