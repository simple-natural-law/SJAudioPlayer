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
#import "SJAudioDataProvider.h"
#import "SJAudioFileStream.h"
#import "SJAudioOutputQueue.h"
#import "SJParsedAudioData.h"
#import "SJAudioBuffer.h"


@interface SJAudioPlayer ()<SJAudioFileStreamDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, strong) SJAudioFileStream *audioFileStream;

@property (nonatomic, strong) SJAudioOutputQueue *audioQueue;

@property (nonatomic, strong) SJAudioDataProvider *dataProvider;

@property (nonatomic, strong) SJAudioBuffer *buffer;

@property (nonatomic, strong) NSString *cachePath;

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, assign) NSUInteger bufferSize;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL readDataCompleted;

@property (nonatomic, assign) BOOL stopReadDataRequired;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) NSTimeInterval seekTime;

@property (nonatomic,readwrite, strong) NSString *urlString;

@property (nonatomic,readwrite, assign) NSUInteger contentLength;

@property (nonatomic,readwrite, assign) NSTimeInterval duration;

@property (nonatomic,readwrite, assign) SJAudioPlayerStatus status;

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithUrlString:(NSString *)url cachePath:(NSString *)cachePath
{
    NSAssert(url, @"url should be not nil");
    
    self = [super init];
    
    if (self)
    {
        self.urlString  = url;
        self.cachePath  = cachePath;
        self.bufferSize = kDefaultBufferSize;
        self.started    = NO;
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}

- (void)cleanUpReadDataThread
{
    [self.audioFileStream close];
    [self.dataProvider close];
    
    self.audioFileStream = nil;
    self.dataProvider  = nil;
    
    self.readDataCompleted    = NO;
    self.stopReadDataRequired = NO;
    
    self.contentLength = 0;
}

- (void)cleanUpPlayAudioThread
{
    self.started   = NO;
    self.status    = SJAudioPlayerStatusStopped;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    self.buffer        = nil;
    self.byteOffset    = 0;
    self.audioQueue    = nil;
}


#pragma mark - methods
/**
 *  播放
 */
- (void)play
{
    if (!self.started)
    {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        // 激活音频会话控制
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        [self start];
        
    }else
    {
        [self resume];
    }
}


- (void)start
{
    self.started = YES;
    
    NSThread  *readDataThread = [[NSThread alloc] initWithTarget:self selector:@selector(enqueneAudioData) object:nil];
    
    [readDataThread setName:@"Read Data Thread"];
    
    [readDataThread start];
    
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"Play Audio Thread"];
    
    [playAudioThread start];
}


- (void)pause
{
    pthread_mutex_lock(&_mutex);
    self.pauseRequired = YES;
    pthread_mutex_unlock(&_mutex);
}


- (void)resume
{
    pthread_mutex_lock(&_mutex);
    if (self.pauseRequired)
    {
        pthread_cond_signal(&_cond);    // 解除阻塞
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)stop
{
    pthread_mutex_lock(&_mutex);
    
    if (self.status != SJAudioPlayerStatusStopped)
    {
        self.stopRequired = YES;
        
        self.stopReadDataRequired = YES;
        
        if (self.pauseRequired)
        {
            pthread_cond_signal(&_cond);    // 解除阻塞
        }
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)seekToProgress:(NSTimeInterval)timeOffset
{
    self.seekTime = timeOffset;
    
    if (self.readDataCompleted)
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
            self.dataProvider = nil;
        }
    }
}


- (void)enqueneAudioData
{
    NSError *error = nil;
    NSError *readDataError = nil;
    NSError *parseDataError = nil;
    
    while (!self.readDataCompleted && !self.stopReadDataRequired)
    {
        if (!self.dataProvider)
        {
            self.dataProvider = [[SJAudioDataProvider alloc] initWithURL:[NSURL URLWithString:self.urlString] cacheFilePath:self.cachePath byteOffset:self.byteOffset];
        }
        
        NSData *data = [self.dataProvider readDataWithMaxLength:self.bufferSize error:&readDataError completed:&_readDataCompleted];
        
        if (readDataError)
        {
            NSLog(@"read data: error");
            
            break;
        }
        
        if (self.dataProvider.contentLength && !self.audioFileStream)
        {
            self.contentLength   = self.dataProvider.contentLength;
            
            self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:hintForFileExtension([NSURL URLWithString:self.urlString].pathExtension) fileSize:self.contentLength error:&error];
            
            self.audioFileStream.delegate = self;
            
            self.buffer = [SJAudioBuffer buffer];
        }
        
        if (self.audioFileStream)
        {
            [self.audioFileStream parseData:data error:&parseDataError];
        }
    }
    
    if (self.stopReadDataRequired)
    {
        NSLog(@"read data: stop");
    }
    
    if (self.readDataCompleted)
    {
        NSLog(@"read data: completed");
    }
    
    [self cleanUpReadDataThread];
}


- (void)playAudioData
{
    while (!self.stopRequired && self.status != SJAudioPlayerStatusFinished) {
        
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
        
        if (self.audioQueue)
        {
            if ([self.buffer hasData])
            {
                UInt32 packetCount;
                
                AudioStreamPacketDescription *desces = NULL;
                
                if ([self.buffer bufferedSize] >= self.bufferSize)
                {
                    NSData *data = [self.buffer dequeueDataWithSize:(UInt32)self.bufferSize packetCount:&packetCount descriptions:&desces];
                    
                    [self.audioQueue playData:data packetCount:packetCount packetDescriptions:desces completed:self.readDataCompleted];
                    
                }else
                {
                    NSData *data = [self.buffer dequeueDataWithSize:[self.buffer bufferedSize] packetCount:&packetCount descriptions:&desces];
                    
                    [self.audioQueue playData:data packetCount:packetCount packetDescriptions:desces completed:self.readDataCompleted];
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
    }
    
    if (self.stopRequired)
    {
        [self.audioQueue stop:YES];
        
        NSLog(@"play audio: stop");
    }
    
    [self cleanUpPlayAudioThread];
}


- (void)createAudioQueue
{
    NSData *magicCookie = [self.audioFileStream fetchMagicCookie];
    
    AudioStreamBasicDescription format = self.audioFileStream.format;
    
    self.audioQueue = [[SJAudioOutputQueue alloc] initWithFormat:format bufferSize:(UInt32)self.bufferSize macgicCookie:magicCookie];
    
    if (!self.audioQueue.available)
    {
        self.audioQueue = nil;
    }
}


- (NSTimeInterval)duration
{
    return self.audioFileStream.duration;
}

#pragma mark- SJAudioFileStreamDelegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    [self.buffer enqueueFromDataArray:audioData];
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
        
    }else if ([fileExtension isEqual:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
        
    }else if ([fileExtension isEqual:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
        
    }else if ([fileExtension isEqual:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
        
    }else if ([fileExtension isEqual:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
        
    }else if ([fileExtension isEqual:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
        
    }else if ([fileExtension isEqual:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
        
    }else if ([fileExtension isEqual:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    return fileTypeHint;
}

@end

