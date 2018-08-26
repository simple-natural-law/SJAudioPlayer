//
//  SJAudioQueue.h
//  SJAudioStream
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


@interface SJAudioQueue : NSObject

@property (nonatomic, assign,readonly) BOOL available; // audioqueue 是否可用

@property (nonatomic, assign,readonly) AudioStreamBasicDescription format;

@property (nonatomic, assign) float volume;

@property (nonatomic, assign) UInt32  bufferSize;

@property (nonatomic, assign, readonly) BOOL isRuning;

/**
 *  return playedTime of audioqueue, return invalidPlayedTime when error occurs.
 */
@property (nonatomic, assign, readonly) NSTimeInterval playedTime;

- (instancetype)initWithFormat:(AudioStreamBasicDescription)format bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie;


/*
 play audio data, data length must be less than bufferSize.
 will block current thread until the buffer is consumed.
 
 @param    data               data
 @param    packetCount        packet count
 @param    packetDescription  packet descriptions
 @param    completed          End of file
 
 @return whether successfully played
 */
- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions completed:(BOOL)completed;

/*
 pause & resume
 */
- (void)pause;

- (BOOL)resume;

/*
 Stop audioqueue
 
 @param      immediately if pass yes, the queue will immediately be stopped,    if pass NO, the queue will be stopped after all buffers are flushed(the same job as -flush)
 
 @return  whether is audioqueue successfully stopped
 
 */
- (BOOL)stop:(BOOL)immediately;

/*
 reset queue
 use when seeking.
 
 @return whether is audioqueue successfully reseted.
 */
- (BOOL)reset;


/*
 flush data
 use when audio data reaches eof
 
 if -stop:(NO) is called this method will do nothing
 
 @return whether is audioqueue successfully flushed
 */
- (BOOL)flush;

/*
   AudioToolBox有很多参数和属性可以设置、获取、监听:
 
   //参数相关方法
   AudioQueueGetParameter
   AudioQueueSetParameter
 
   //属性相关方法
   AudioQueueGetPropertySize
   AudioQueueGetProperty
   AudioQueueSetProperty
 
   //监听属性变化相关方法
   AudioQueueAddPropertyListener
   AudioQueueRemovePropertyListener
 
 //属性列表
 enum { // typedef UInt32 AudioQueuePropertyID
 
       kAudioQueueProperty_IsRunning               = 'aqrn',       // value is UInt32
 
       kAudioQueueDeviceProperty_SampleRate        = 'aqsr',       // value is Float64
       kAudioQueueDeviceProperty_NumberChannels    = 'aqdc',       // value is UInt32
       kAudioQueueProperty_CurrentDevice           = 'aqcd',       // value is CFStringRef
 
       kAudioQueueProperty_MagicCookie             = 'aqmc',       // value is void*
       kAudioQueueProperty_MaximumOutputPacketSize = 'xops',       // value is UInt32
       kAudioQueueProperty_StreamDescription       = 'aqft',       // value is AudioStreamBasicDescription
 
       kAudioQueueProperty_ChannelLayout           = 'aqcl',       // value is AudioChannelLayout
       kAudioQueueProperty_EnableLevelMetering     = 'aqme',       // value is UInt32
       kAudioQueueProperty_CurrentLevelMeter       = 'aqmv',       // value is array of AudioQueueLevelMeterState, 1 per channel
       kAudioQueueProperty_CurrentLevelMeterDB     = 'aqmd',       // value is array of AudioQueueLevelMeterState, 1 per channel
 
       kAudioQueueProperty_DecodeBufferSizeFrames  = 'dcbf',       // value is UInt32
       kAudioQueueProperty_ConverterError          = 'qcve',       // value is UInt32
 
       kAudioQueueProperty_EnableTimePitch         = 'q_tp',       // value is UInt32, 0/1
       kAudioQueueProperty_TimePitchAlgorithm      = 'qtpa',       // value is UInt32. See values below.
       kAudioQueueProperty_TimePitchBypass         = 'qtpb',       // value is UInt32, 1=bypassed
 };
 

 //参数列表
 enum    // typedef UInt32 AudioQueueParameterID;
 {
     kAudioQueueParam_Volume         = 1,
     kAudioQueueParam_PlayRate       = 2,
     kAudioQueueParam_Pitch          = 3,
     kAudioQueueParam_VolumeRampTime = 4,
     kAudioQueueParam_Pan            = 13
 };
 
 kAudioQueueProperty_IsRunning监听它可以知道当前AudioQueue是否在运行。
 
 kAudioQueueProperty_MagicCookie部分音频格式需要设置magicCookie，这个cookie可以从AudioFileStream和AudioFile中获取。
 
 kAudioQueueParam_Volume，它可以用来调节AudioQueue的播放音量，注意这个音量是AudioQueue的内部播放音量和系统音量相互独立设置并且最后叠加生效。
 
 kAudioQueueParam_VolumeRampTime参数和Volume参数配合使用可以实现音频播放淡入淡出的效果；
 
 kAudioQueueParam_PlayRate参数可以调整播放速率；
 
 */

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError **)outError;
- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError **)outError;
- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue)value error:(NSError **)outError;
- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError **)outError;

@end
