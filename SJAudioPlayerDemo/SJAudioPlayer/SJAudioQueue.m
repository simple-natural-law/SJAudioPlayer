//
//  SJAudioQueue.m
//  SJAudioPlayer
//
//  Created by 张诗健 on 16/12/30.
//  Copyright © 2016年 张诗健. All rights reserved.
//



#import "SJAudioQueue.h"
#import <pthread.h>


@interface SJAudioQueueBuffer : NSObject

@property (nonatomic, assign) AudioQueueBufferRef audioQueueBufferRef;

@end

@implementation SJAudioQueueBuffer

@end

/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////

static int const SJAudioQueueBufferCount = 3;

@interface SJAudioQueue ()
{
    pthread_mutex_t _mutex;
    pthread_cond_t _cond;
}

@property (nonatomic, assign) AudioQueueRef audioQueue;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, strong) NSMutableArray<SJAudioQueueBuffer *> *reusableBufferArray;

@property (nonatomic, assign) BOOL available;

@property (nonatomic, assign) BOOL isRunning;

@property (nonatomic, assign) AudioStreamBasicDescription format;

@property (nonatomic, assign) NSTimeInterval playedTime;

@end


@implementation SJAudioQueue

- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithFormat:(AudioStreamBasicDescription)format bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie
{
    self = [super init];
    
    if (self)
    {
        self.format = format;
        self.volume = 0.0f;
        self.bufferSize = bufferSize;

        [self createAudioQueueWithMagicCookie:macgicCookie];
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}



/*
 使用下列方法来生成AudioQueue的实例
 
 OSStatus AudioQueueNewOutput (const AudioStreamBasicDescription * inFormat,
                               AudioQueueOutputCallback inCallbackProc,
                               void * inUserData,
                               CFRunLoopRef inCallbackRunLoop,
                               CFStringRef inCallbackRunLoopMode,
                               UInt32 inFlags,
                               AudioQueueRef * outAQ);
 
 第一个参数表示需要播放的音频数据格式类型，是一个`AudioStreamBasicDescription`对象，是使用 `AudioFileStream`或`AudioFile`解析出来的数据格式信息；
 第二个参数`AudioQueueOutputCallBack`是某块Buffer被使用之后的回调;
 第三个参数为上下文对象；
 第四个参数`inCallbackRunLoop`是`AudioQueueOutputCallback`需要在哪个Runloop上调用，如果传入NULL的话就会在AudioQueue的内部Runloop中调用，所以一般传NULL就可以了。
 第五个参数`inCallbackRunLoopMode`为Runloop模式，如果传入NULL就相当于kCFRunLoopCommonModes，也传NULL就可以了。
 第六个参数`inFlags`是保留字段，目前没有作用，传0；
 第七个参数，返回生成的`AudioQueue`实例。
 返回值，用来判断是否成功创建。
 
 OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef * outAQ,
                                               const AudioStreamBasicDescription * inFormat,
                                               UInt32 inFlags,
                                               dispatch_queue_t inCallbackDispatchQueue,
                                            AudioQueueOutputCallbackBlock inCallbackBlock);
 
 第二个方法就是把Runloop替换成了一个dispatch queue， 其余参数同相同。
*/
- (void)createAudioQueueWithMagicCookie:(NSData *)magicCookie
{
    OSStatus status = AudioQueueNewOutput(&_format, SJAudioQueueOutputCallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &_audioQueue);
    
    if (status != noErr)
    {
        self.audioQueue = NULL;
        
        return;
    }
    
    status = AudioQueueAddPropertyListener(self.audioQueue, kAudioQueueProperty_IsRunning, SJAudioQueuePropertyCallback, (__bridge void * _Nullable)(self));
    
    if (status != noErr)
    {
        AudioQueueDispose(self.audioQueue, true);
        
        self.audioQueue = NULL;
        
        return;
    }

    self.reusableBufferArray = [[NSMutableArray alloc] initWithCapacity:SJAudioQueueBufferCount];
    
    for (int i = 0; i < SJAudioQueueBufferCount; i++)
    {
        /*
         创建AudioQueueBufferRef实例
         
         传入 AudioQueue 实例和 Buffer 的大小， 传出 AudioQueueBufferRef 实例。
        */
        AudioQueueBufferRef bufferRef;
        
        status = AudioQueueAllocateBuffer(self.audioQueue, self.bufferSize, &bufferRef);
        
        if (status != noErr)
        {
            // 调用`AudioQueueDispose`函数时，会自动清除所有buffer。
            AudioQueueDispose(self.audioQueue, true);
            self.audioQueue = NULL;
            break;
        }
        
        SJAudioQueueBuffer *buffer = [[SJAudioQueueBuffer alloc] init];
        
        buffer.audioQueueBufferRef = bufferRef;
        
        [self.reusableBufferArray addObject:buffer];
    }

#if TARGET_OS_IPHONE
    UInt32 property = kAudioQueueHardwareCodecPolicy_PreferSoftware;
    [self setProperty:kAudioQueueProperty_HardwareCodecPolicy dataSize:sizeof(property) data:&property error:NULL];
#endif
    
    if (magicCookie)
    {
        AudioQueueSetProperty(self.audioQueue, kAudioQueueProperty_MagicCookie, [magicCookie bytes], (UInt32)[magicCookie length]);
    }
    
    [self setParameter:kAudioQueueParam_Volume value:self.volume error:NULL];
}

// 设置音频倍速播放
- (void)setAudioQueuePlayRate:(float)playRate
{
    UInt32 enable = true;
    
    [self setProperty:kAudioQueueProperty_EnableTimePitch dataSize:sizeof(enable) data:&enable error:NULL];
    
    UInt32 algorithm = kAudioQueueTimePitchAlgorithm_Spectral;
    
    [self setProperty:kAudioQueueProperty_TimePitchAlgorithm dataSize:sizeof(algorithm) data:&algorithm error:NULL];
    
    [self setParameter:kAudioQueueParam_PlayRate value:playRate error:NULL];
}


/*
 销毁 AudioQueue，同时自动清除所有的 buffer
 
 这个方法使用时需要注意当`AudioQueueStart`调用之后AudioQueue其实还没有真正开始，期间会有一个短暂的间隙。
 如果在`AudioQueueStart`调用后到AudioQueue真正开始运作前的这段时间内调用`AudioQueueDispose`方法的话会导
 致程序卡死。
*/
- (void)disposeAudioQueue
{
    if (self.audioQueue != NULL)
    {
        AudioQueueDispose(self.audioQueue, true);
        
        self.audioQueue = NULL;
    }
}



/*
 开始播放
 
 OSStatus AudioQueueStart(AudioQueueRef inAQ,const AudioTimeStamp * inStartTime);
  
 第二个参数可以用来控制播放开始的时间，一般情况下直接开始播放传入 NULL 即可。
*/
- (BOOL)start
{
    OSStatus status = AudioQueueStart(self.audioQueue, NULL);
    
    [self setVolume:1.0];
    
    self.started = (status == noErr);
    
    return self.started;
}



/// 恢复播放
- (BOOL)resume
{
    return [self start];
}


/*
 暂停播放
 
 OSStatus AudioQueuePause(AudioQueueRef inAQ);

 注意：
 这个方法一旦调用后播放就会立即暂停，这就意味着`AudioQueueOutputCallback`回调也会暂停，这时需
 要特别关注线程的调度以防止线程陷入无限等待（音频播放被打断时，要特别注意这个情况）。
*/
- (void)pause
{
    [self setVolume:0.0];
    
    // 让播放声音大小淡出之后，再暂停。
    [NSThread sleepForTimeInterval:0.4];
    
    OSStatus status = AudioQueuePause(self.audioQueue);
    
    if (status != noErr)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioQueue: failed to pasue audio queue.");
        }
    }
}


/*
 停止播放
 
 OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate);
 
 第二个参数如果传入true的话会立即停止播放（同步），如果传入`false`的话，AudioQueue会播放完已经 Enqueue
 的所有 buffer 后再停止播放（异步）。使用时注意根据需要传入适合的参数。
*/
- (BOOL)stop:(BOOL)immediately
{    
    OSStatus status = noErr;
    
    if (immediately)
    {
        status = AudioQueueStop(self.audioQueue, true);
    }else
    {
        status = AudioQueueStop(self.audioQueue, false);
        
        while (self.isRuning)
        {
            [NSThread sleepForTimeInterval:0.1];
        }
    }
    
    self.started    = NO;
    self.playedTime = 0.0;
    
    return status == noErr;
}


/*
 重置 AudioQueue 的解码器状态信息
 
 OSStatus  AudioQueueFlush(AudioQueueRef inAQ);
 
 调用此函数后，会播放完Enqueue的所有 buffer, 然后后重置解码器状态信息，以防止当前的解码器状态影响到下一段音
 频的解码(比如切换播放的歌曲时)。 如果和`AudioQueueStop(AQ，false)`一起使用并不会起效，因为 stop 方法的
 false参数也会做同样的事情。
*/
- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(self.audioQueue);
    
    return status == noErr;
}


/*
 重置 AudioQueue
 
 OSStatus AudioQueueReset(AudioQueueRef inAQ);
 
 重置 AudioQueue 会清除所有已经 Enqueue 的buffer， 并触发 AudioQueueOutputCallback ，调用
 AudioQueueStop 方法时同样会触发该方法。这个方法的直接调用一般在seek时使用，用来清除残留的buffer（seek时
 还有一种做法是先 AudioQueueStop ，等seek完成后重新start）。
*/
- (BOOL)reset
{
    OSStatus status = AudioQueueReset(self.audioQueue);
    
    [self setVolume:1.0];
    
    return status == noErr;
}


/*
 播放音频数据，音频数据长度必须小于AudioQueueBufferRef的size。
 
 还需要传入音频数据中包含的音频帧个数和每个音频帧的描述信息。
*/
- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof
{
    if ([data length] > self.bufferSize)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioQueue: size of the data will be played is more than the `bufferSize`.");
        }
        
        return NO;
    }
    
    pthread_mutex_lock(&_mutex);
    if (self.reusableBufferArray.count == 0)
    {
        pthread_cond_wait(&_cond, &_mutex);
    }
    pthread_mutex_unlock(&_mutex);
    
    AudioQueueBufferRef bufferRef = self.reusableBufferArray.firstObject.audioQueueBufferRef;
    
    pthread_mutex_lock(&_mutex);
    [self.reusableBufferArray removeObjectAtIndex:0];
    pthread_mutex_unlock(&_mutex);
    
    OSStatus status;
    
    if (!bufferRef)
    {
        status = AudioQueueAllocateBuffer(self.audioQueue, self.bufferSize, &bufferRef);
        
        if (status != noErr)
        {
            return NO;
        }
    }
    
    // 将 data 拷贝到 buffer 中
    memcpy(bufferRef->mAudioData, [data bytes], [data length]);
    
    bufferRef->mAudioDataByteSize = (UInt32)[data length];
    
    // 插入 buffer
    status = AudioQueueEnqueueBuffer(self.audioQueue, bufferRef, packetCount, packetDescriptions);
    
    if (status == noErr)
    {
        pthread_mutex_lock(&_mutex);
        NSUInteger reusableBufferCount = self.reusableBufferArray.count;
        pthread_mutex_unlock(&_mutex);
        
        // 等到插满所有buffer后才开始播放
        if (reusableBufferCount == 0 || isEof)
        {
            if (!self.started)
            {
                BOOL success = [self start];
                
                if (!success)
                {
                    return NO;
                }
            }
        }
    }
    
    return status == noErr;
}



/*
 获取播放时长
 
 需要注意的是这个播放时间是指实际播放的时间，和播放进度是有区别的。举个例子，开始播放8秒后用
 户操作slider把播放进度seek到了第20秒之后又播放了3秒钟，此时通常意义上播放时间应该是23秒，即播放进度。而用
 GetCurrentTime方法中获得的时间为11秒，即实际播放时间。所以每次seek时都必须保存seek的timingOffset：
 
 AudioTimeStamp time = ...; （AudioQueueGetCurrentTime方法获取）
 
 NSTimeInterval playedTime = time.mSampleTime / _format.mSampleRate; （seek时的播放时间）
 
 NSTimeInterval seekTime = ...; （需要seek到哪个时间）
 
 NSTimeInterval timingOffset = seekTime - playedTime;
 
 seek后的播放进度需要根据timingOffset和playedTime计算：NSTimeInterval progress = timingOffset + playedTime;
 
 第二个需要注意的是GetCurrentTime方法有时候会失败，所以上次获取的播放时间最好保存起来，如果遇到调用失败，就返回上次保存的结果。
*/
- (NSTimeInterval)playedTime
{
    if (_format.mSampleRate == 0)
    {
        return 0.0;
    }
    
    AudioTimeStamp time;
    
    OSStatus status = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
    
    if (status == noErr)
    {
        _playedTime = time.mSampleTime / _format.mSampleRate;
    }
    
    return _playedTime;
}


- (BOOL)available
{
    return self.audioQueue != NULL;
}


- (void)setVolume:(float)volume
{
    _volume = volume;
    
    [self setVolumeParameter];
}


- (void)setVolumeParameter
{
    // 音频淡入淡出， 首先设置音量渐变过程使用的时间。
    [self setParameter:kAudioQueueParam_VolumeRampTime value:(self.volume > 0.0 ? 0.6 : 0.4) error:NULL];
    
    [self setParameter:kAudioQueueParam_Volume value:self.volume error:NULL];
}


/*
 当 AudioQueue 播放完一个 Buffer 时，会在使用`AudioQueueNewOutput`函数创建AudioQueue时指定的
 runloop中调用一次此函数。如果没有指定runloop，则会在AudioQueue自己的线程中调用此函数。
 */
static void SJAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    SJAudioQueue *audioOutputQueue = (__bridge SJAudioQueue *)(inClientData);
    
    [audioOutputQueue handleAudioQueueOutputCallBack:inAQ buffer:inBuffer];
}


- (void)handleAudioQueueOutputCallBack:(AudioQueueRef)audioQueue buffer:(AudioQueueBufferRef)buffer
{
    SJAudioQueueBuffer *audioQueueBuffer = [[SJAudioQueueBuffer alloc] init];
    
    audioQueueBuffer.audioQueueBufferRef = buffer;
    
    
    pthread_mutex_lock(&_mutex);
    
    [self.reusableBufferArray addObject:audioQueueBuffer];
    
    pthread_cond_signal(&_cond);
    
    pthread_mutex_unlock(&_mutex);
}


static void SJAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    SJAudioQueue *audioQueue = (__bridge SJAudioQueue *)(inUserData);
    
    [audioQueue handleAudioQueuePropertyCallBack:inAQ property:inID];
}


- (void)handleAudioQueuePropertyCallBack:(AudioQueueRef)audioQueue property:(AudioQueuePropertyID)property
{
    if (property == kAudioQueueProperty_IsRunning)
    {
        UInt32 isRuning = 0;
        
        UInt32 size = sizeof(isRuning);
        
        AudioQueueGetProperty(audioQueue, property, &isRuning, &size);
        
        self.isRunning = isRuning;
    }
}



- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetProperty(self.audioQueue, propertyID, data, dataSize);

    return status == noErr;
}


- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetProperty(self.audioQueue, propertyID, data, dataSize);

    return status == noErr;
}



- (BOOL)setParameter:(AudioQueueParameterID)parameterID value:(AudioQueueParameterValue)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetParameter(self.audioQueue, parameterID, value);

    return status == noErr;
}



- (BOOL)getParameter:(AudioQueueParameterID)parameterID value:(AudioQueueParameterValue *)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetParameter(self.audioQueue, parameterID, value);

    return status == noErr;
}

@end
