//
//  SJAudioOutputQueue.m
//  SJAudioStream
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//



#pragma -mark 
/*
   在使用AudioQueue之前首先必须理解其工作模式，它之所以这么命名是因为在其内部有一套缓冲队列（Buffer Queue）的机制。在AudioQueue
 启动之后需要通过AudioQueueAllocateBuffer生成若干个AudioQueueBufferRef结构，这些Buffer将用来存储即将要播放的音频数据，并且这
 些Buffer是受生成他们的AudioQueue实例管理的，内存空间也已经被分配（按照Allocate方法的参数），当AudioQueue被Dispose时这些
 Buffer也会随之被销毁。
    当有音频数据需要被播放时首先需要被memcpy到AudioQueueBufferRef的mAudioData中（mAudioData所指向的内存已经被分配，之前
 AudioQueueAllocateBuffer所做的工作），并给mAudioDataByteSize字段赋值传入的数据大小。完成之后需要调用
 AudioQueueEnqueueBuffer把存有音频数据的Buffer插入到AudioQueue内置的Buffer队列中。在Buffer队列中有buffer存在的情况下调用
 AudioQueueStart，此时AudioQueue就回按照Enqueue顺序逐个使用Buffer队列中的buffer进行播放，每当一个Buffer使用完毕之后就会从
 Buffer队列中被移除并且在使用者指定的RunLoop上触发一个回调来告诉使用者，某个AudioQueueBufferRef对象已经使用完成，你可以继续重用
 这个对象来存储后面的音频数据。如此循环往复音频数据就会被逐个播放直到结束。
 
*/






#pragma -mark 
/*
 AudioQueue工作原理：
 1.创建audioqueue，创建一个自己的buffer数组bufferarray
 2.使用 AudioQueueAllocateBuffer 创建若干个AudioQueueBufferRef（一般2-3个即可）
 3.有数据时从bufferArray取出一个buffer，memcpy数据后用 AudioQueueEnqueueBuffer 方法把buffer插入AudioQueue中；
 4.AudioQueue 中存在buffer后，调用 AudioQueueStart 播放。（具体等到填入多少buffer后再播放开源自己控制，只要能保证播放不间断即可）；
 5.AudioQueue 播放音乐后消耗了某个buffer， 在另一个线程回调并送出该buffer ，把buffer放回bufferArray供下一次使用；
 6.返回步骤3继续循环知道播放结束。
 */



#import "SJAudioOutputQueue.h"
#import <pthread.h>
#import <AudioToolbox/AudioToolbox.h>

#define SJAudioQueueBufferCount 16


@interface SJAudioOutputQueue ()
{
    pthread_mutex_t _mutex;
    pthread_cond_t _cond;
    
    AudioQueueBufferRef audioQueueBuffer[SJAudioQueueBufferCount];
    
    bool inuse[SJAudioQueueBufferCount];
}

@property (nonatomic, assign) AudioQueueRef audioQueue;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) NSUInteger fillBufferIndex;;

@property (nonatomic, assign) NSUInteger bufferUsed;

@property (nonatomic, assign, readwrite) BOOL available;

@property (nonatomic, assign, readwrite) BOOL isRunning;

@property (nonatomic, assign, readwrite) AudioStreamBasicDescription format;

@property (nonatomic, assign, readwrite) NSTimeInterval playedTime;

@end

@implementation SJAudioOutputQueue


- (instancetype)initWithFormat:(AudioStreamBasicDescription)format bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie
{
    self = [super init];
    
    if (self)
    {
        self.format = format;
        self.volume = 0.0f;
        self.bufferSize = bufferSize;

        [self createAudioOutputQueue:macgicCookie];
        [self mutexInit];
    }
    return self;
}

- (void)dealloc
{
    [self disposeAudioOutputQueue];
    [self mutexDestory];
}


- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL)
    {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma -mark
- (void)mutexInit
{
    pthread_mutex_init(&_mutex, NULL); // 初始化 锁
    pthread_cond_init(&_cond, NULL);
}

- (void)mutexDestory
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}

- (void)mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex);
    pthread_mutex_unlock(&_mutex);
}

- (void)mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}

#pragma -mark  audio queue
/*
  使用下列方法来生成AudioQueue的实例
 
 OSStatus AudioQueueNewOutput (const AudioStreamBasicDescription * inFormat,
                               AudioQueueOutputCallback inCallbackProc,
                               void * inUserData,
                               CFRunLoopRef inCallbackRunLoop,
                               CFStringRef inCallbackRunLoopMode,
                               UInt32 inFlags,
                               AudioQueueRef * outAQ);
 
 第一个参数表示需要播放的音频数据格式类型，是一个 AudioStreamBasicDescription 对象，是使用 AudioFileStream 或 AudioFile 解析出来的数据格式信息；
 第二个参数 AudioQueueOutputCallback 是某块 Buffer 被使用之后的回调;
 第三个参数为上下文对象；
 第四个参数 inCallbackRunLoop 为 AudioQueueOutputCallback 需要在哪个Runloop上被回调，如果传入NULL的话就会在AudioQueue的内部Runloop中被回调，所以一般传NULL久可以了。
 第五个参数 inCallbackRunLoopMode 为Runloop模式，如果传入NULL就相当于kCFRunLoopCommonModes，也传NULL就可以了。
 第六个参数inFlags是保留字段，目前没有作用，传0；
 第七个参数，返回生成的 AudioQueue 实例。
 返回值用来判断是否成功创建。
 
 OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef * outAQ,
                                               const AudioStreamBasicDescription * inFormat,
                                               UInt32 inFlags,
                                               dispatch_queue_t inCallbackDispatchQueue,
                                            AudioQueueOutputCallbackBlock inCallbackBlock);
 
 第二个方法就是把 Runloop 替换成了一个dispatch queue， 其余参数同相同
 
 */
- (void)createAudioOutputQueue:(NSData *)magicCookie
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
    

    for (int i = 0; i < SJAudioQueueBufferCount; ++i) {
//            AudioQueueBufferRef buffer;
        
/*
  OSStatus AudioQueueAllocateBuffer(AudioQueueRef inAQ,
                                  UInt32 inBufferByteSize,
                                  AudioQueueBufferRef * outBuffer);
 
  传入 AudioQueue 实例 和 Buffer大小， 传出 buffer 实例；
 
  OSStatus AudioQueueAllocateBufferWithPacketDescriptions(AudioQueueRef inAQ,
                                                         UInt32 inBufferByteSize,
                                                         UInt32 inNumberPacketDescriptions,
                                                         AudioQueueBufferRef * outBuffer);
  
  这个方法可以指定生成的buffer中PacketDescriptions的个数；
 
 
  销毁Buffer:
  OSStatus AudioQueueFreeBuffer(AudioQueueRef inAQ,AudioQueueBufferRef inBuffer);
 
  注意这个方法一般只在需要销毁特定某个buffer时才会被用到（因为dispose方法会自动销毁所有buffer），并且这个方法只能在AudioQueue不在处理数据时才能使用。所以这个方法一般不太能用到。
 */
            // 创建 buffer
            status = AudioQueueAllocateBuffer(self.audioQueue, self.bufferSize, &audioQueueBuffer[i]);
        
            if (status != noErr)
            {
                AudioQueueDispose(self.audioQueue, true);
                self.audioQueue = NULL;
                break;
            }
        
    }


#if TARGET_OS_IPHONE
    UInt32 property = kAudioQueueHardwareCodecPolicy_PreferSoftware;
    [self setProperty:kAudioQueueProperty_HardwareCodecPolicy dataSize:sizeof(property) data:&property error:NULL];
#endif
    if (magicCookie) {
        AudioQueueSetProperty(self.audioQueue, kAudioQueueProperty_MagicCookie, [magicCookie bytes], (UInt32)[magicCookie length]);
    }
    
    [self setParameter:kAudioQueueParam_Volume value:self.volume error:NULL];
}



// 销毁 audioqueue
/*
 
  AudioQueueDispose(AudioQueueRef inAQ,  Boolean inImmediate);
 
  销毁的同时会清除其中所有的 buffer ，第二个参数的意义和用法与audioqueue方法相同.
 
 这个方法使用时需要注意当AudioQueueStart调用之后AudioQueue其实还没有真正开始，期间会有一个短暂的间隙。如果在AudioQueueStart调用后到AudioQueue真正开始运作前的这段时间内调用AudioQueueDispose方法的话会导致程序卡死。
 */
- (void)disposeAudioOutputQueue
{
    if (self.audioQueue != NULL)
    {
        AudioQueueDispose(self.audioQueue, true);
        
        self.audioQueue = NULL;
    }
}




// 开始播放
/*
 
  OSStatus AudioQueueStart(AudioQueueRef inAQ,const AudioTimeStamp * inStartTime);
  
  第二个参数可以用来控制播放开始的时间，一般情况下直接开始播放传入 NULL 即可。
 
 */
- (BOOL)start
{
    OSStatus status = AudioQueueStart(self.audioQueue, NULL);
    
    [self setVolume:1.0];
    
    _started = status == noErr;
    
    return _started;
}






// 恢复播放
- (BOOL)resume
{
    return [self start];
}




// 暂停播放
/*
 
  OSStatus AudioQueuePause(AudioQueueRef inAQ);
  
  这个方法一旦调用后播放就会立即暂停，这就意味着 AudioQueueOutputCallback 回调也会暂停，这时需要特别关注线程的调度以防止线程陷入无限等待。
 
 */
- (void)pause
{
    [self setVolume:0];
    
    OSStatus status = AudioQueuePause(self.audioQueue);
    
    self.started = status == noErr;
}


// 停止播放
/*
 
  OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate);
 
  第二个参数如果传入true的话会立即停止播放（同步），如果传入false的话AudioQueue会播放完已经 Enqueue 的所有 buffer 后再停止播放（异步）。使用时注意根据需要传入适合的参数。
 
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
    }
    
    self.started    = NO;
    self.playedTime = 0;
    
    return status == noErr;
}





// Flush
/*
 
  OSStatus  AudioQueueFlush(AudioQueueRef inAQ);
 
  调用后会播放完Enqueue的所有 buffer 后重置解码器状态，以防止当前的解码器状态影响到下一段音频的解码(比如切换播放的歌曲时)。 如果和AudioQueueStop（AQ，false）一起使用并不会起效，因为 stop 方法的false参数也会做同样的事情。
 */
- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(self.audioQueue);
    return status == noErr;
}




// 重置
/*
  
  OSStatus AudioQueueReset(AudioQueueRef inAQ);
 
  重置 AudioQueue 会清除所有已经 Enqueue 的buffer， 并触发 AudioQueueOutputCallback ， 调用 AudioQueueStop 方法时同样会触发该方法。这个方法的直接调用一般在seek时使用，用来清除残留的buffer（seek时还有一种做法是先 AudioQueueStop ，等seek完成后重新start）。
 
 */
- (BOOL)reset
{
    OSStatus status = AudioQueueReset(self.audioQueue);
    return status == noErr;
}





- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions completed:(BOOL)completed
{
    if ([data length] > self.bufferSize)
    {
        return NO;
    }

    // 如果还没有开始播放
//    if (!_started && ![self start]) {
//        return NO;
//    }
    
    OSStatus status;
    
    @synchronized(self) {
        
        inuse[self.fillBufferIndex] = true;     // set in use flag
        
        self.bufferUsed++;
        
        AudioQueueBufferRef buffer = audioQueueBuffer[self.fillBufferIndex];
        
        if (!buffer)
        {
            OSStatus status = AudioQueueAllocateBuffer(self.audioQueue, self.bufferSize, &buffer);
            
            if (status != noErr)
            {
                return NO;
            }
        }
    

    // C函数语法 void *memcpy(void*dest, const void *src, size_t n);
    /*
       由src指向地址为起始地址的连续n个字节的数据复制到以destin指向地址为起始地址的空间内。
       
     memcpy用来做内存拷贝，你可以拿它拷贝任何数据类型的对象，可以指定拷贝的数据长度；
     
     1.source和destin所指内存区域不能重叠，函数返回指向destin的指针。
     
     2.与strcpy相比，memcpy并不是遇到'\0'就结束，而是一定会拷贝完n个字节。

     例：
     　　char a[100], b[50];
     　　memcpy(b, a,sizeof(b)); //注意如用sizeof(a)，会造成b的内存地址溢出。
     　　strcpy就只能拷贝字符串了，它遇到'\0'就结束拷贝；例：
     　　char a[100], b[50];
     strcpy(a,b);
     
     3.如果目标数组destin本身已有数据，执行memcpy（）后，将覆盖原有数据（最多覆盖n）。如果要追加数据，则每次执行memcpy后，要将目标数组地址增加到你要追加数据的地址。
     
     注意，source和destin都不一定是数组，任意的可读写的空间均可。
     */
    
    /*
     
     typedef struct AudioQueueBuffer {
     const UInt32                    mAudioDataBytesCapacity;
     void * const                    mAudioData;
     UInt32                          mAudioDataByteSize;
     void * __nullable               mUserData;
     
     const UInt32                    mPacketDescriptionCapacity;
     AudioStreamPacketDescription * const __nullable mPacketDescriptions;
     UInt32                          mPacketDescriptionCount;
     #ifdef __cplusplus
     AudioQueueBuffer() : mAudioDataBytesCapacity(0), mAudioData(0), mPacketDescriptionCapacity(0), mPacketDescriptions(0) { }
     #endif
     } AudioQueueBuffer;

     
     @typedef    AudioQueueBufferRef
     @abstract   An pointer to an AudioQueueBuffer.
     
     typedef AudioQueueBuffer *AudioQueueBufferRef;
     
     */
    
        memcpy(buffer->mAudioData, [data bytes], [data length]);
        
        buffer->mAudioDataByteSize = (UInt32)[data length];
    
    // 插入 buffer
    /*
     
     OSStatus AudioQueueEnqueueBuffer(AudioQueueRef inAQ,
                                      AudioQueueBufferRef inBuffer,
                                      UInt32 inNumPacketDescs,
                                      const AudioStreamPacketDescription * inPacketDescs);
     
     需要传入 AudioQueue 实例，和需要Enqueue的Buffer，对于有inNumPacketDescs和inPacketDescs则需要根据需要选择传入，文档上说这2个参数主要是在播放 VBR 数据时使用，但之前我们提到过即便是CBR数据AudioFileStream或者AudioFile也会给出PacketDescription所以不能如此一概而论。简单的来说就是有就传PacketDescription没有就给NULL，不必管是不是VBR。
     
     Enqueue 方法一共有2个，上面给出的是第一个方法，第二个方法AudioQueueEnqueueBufferWithParameters 可以对Enqueue的buffer进行更多操作。
     
     */
    
        status = AudioQueueEnqueueBuffer(self.audioQueue, buffer, packetCount, packetDescriptions);
        
        
        if (status == noErr)
        {
            // 等到插满 16个buffer后才开始播放
            if (self.bufferUsed == SJAudioQueueBufferCount - 1 || completed)
            {
                if (!self.started && ![self start])
                {
                    return NO;
                }
            }
        }
        
        
        // go to next buffer
        if (++self.fillBufferIndex >= SJAudioQueueBufferCount)
        {
            self.fillBufferIndex = 0;
        }
        
    }
    
    pthread_mutex_lock(&_mutex);
    
    if (inuse[self.fillBufferIndex])
    {
        pthread_cond_wait(&_cond, &_mutex);
    }
    
    pthread_mutex_unlock(&_mutex);
    
    return status == noErr;
}




- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetProperty(self.audioQueue, propertyID, data, dataSize);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}


- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetProperty(self.audioQueue, propertyID, data, dataSize);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}



- (BOOL)setParameter:(AudioQueueParameterID)parameterID value:(AudioQueueParameterValue)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetParameter(self.audioQueue, parameterID, value);
    
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}



- (BOOL)getParameter:(AudioQueueParameterID)parameterID value:(AudioQueueParameterValue *)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetParameter(self.audioQueue, parameterID, value);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

#pragma -mark property
// 获取播放时间
/*
 OSStatus AudioQueueGetCurrentTime(AudioQueueRef inAQ,
                                   AudioQueueTimelineRef inTimeline,
                                   AudioTimeStamp * outTimeStamp,
                                   Boolean * outTimelineDiscontinuity);
 
 传入的参数中，第二，第四个参数是和AudioQueueTimeline相关的，这里并没有用到，传入NULL。 调用后的返回AudioTimeStamp，从这个timestap结构可以得出播放时间。
 
 在使用这个时间获取方法时有两点必须注意：
 
 第一个需要注意的时这个播放时间是指实际播放的时间和一般理解上的播放进度是有区别的。举个例子，开始播放8秒后用
 户操作slider把播放进度seek到了第20秒之后又播放了3秒钟，此时通常意义上播放时间应该是23秒，即播放进度；而用
 GetCurrentTime方法中获得的时间为11秒，即实际播放时间。所以每次seek时都必须保存seek的timingOffset：
 
     AudioTimeStamp time = ...; （AudioQueueGetCurrentTime方法获取）
 
     NSTimeInterval playedTime = time.mSampleTime / _format.mSampleRate; （seek时的播放时间）
 
     NSTimeInterval seekTime = ...; （需要seek到哪个时间）
 
     NSTimeInterval timingOffset = seekTime - playedTime;
 
 seek后的播放进度需要根据timingOffset和playedTime计算：
     NSTimeInterval progress = timingOffset + playedTime;
 
 第二个需要注意的是GetCurrentTime方法有时候会失败，所以上次获取的播放时间最好保存起来，如果遇到调用失败，就返回上次保存的结果。
 */
- (NSTimeInterval)playedTime
{
    if (_format.mSampleRate == 0) {
        return 0;
    }
    
    AudioTimeStamp time;
    
    OSStatus status = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
    
    if (status == noErr) {
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
    [self setParameter:kAudioQueueParam_VolumeRampTime value:1.0 error:NULL];
    [self setParameter:kAudioQueueParam_Volume value:self.volume error:NULL];
}

#pragma -mark call back
static void SJAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,AudioQueueBufferRef inBuffer)
{
    SJAudioOutputQueue *audioOutputQueue = (__bridge SJAudioOutputQueue *)(inClientData);
    [audioOutputQueue handleAudioQueueOutputCallBack:inAQ buffer:inBuffer];
}

- (void)handleAudioQueueOutputCallBack:(AudioQueueRef)audioQueue buffer:(AudioQueueBufferRef)buffer
{
    
    unsigned int bufferIndex = -1;
    
    for (unsigned int i = 0; i < SJAudioQueueBufferCount; ++i) {
        
        if (buffer == audioQueueBuffer[i]) {
            
            bufferIndex = i;
            
            break;
        }
    }
    
    
    pthread_mutex_lock(&_mutex);
    
    inuse[bufferIndex] = false;
    
    self.bufferUsed--;
    
    pthread_cond_signal(&_cond);
    
    pthread_mutex_unlock(&_mutex);
}

static void SJAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    SJAudioOutputQueue *audioQueue = (__bridge SJAudioOutputQueue *)(inUserData);
    [audioQueue handleAudioQueuePropertyCallBack:inAQ property:inID];
}

- (void)handleAudioQueuePropertyCallBack:(AudioQueueRef)audioQueue property:(AudioQueuePropertyID)property
{
    if (property == kAudioQueueProperty_IsRunning) {
        UInt32 isRuning = 0;
        UInt32 size = sizeof(isRuning);
        AudioQueueGetProperty(audioQueue, property, &isRuning, &size);
        self.isRunning = isRuning;
    }
}

@end
