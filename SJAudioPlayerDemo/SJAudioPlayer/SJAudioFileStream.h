//
//  SJAudioFileStream.h
//  SJAudioPlayer
//
//  Created by 张诗健 on 15/12/14.
//  Copyright © 2015年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@class SJAudioFileStream;

@protocol SJAudioFileStreamDelegate <NSObject>

@required
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream receiveInputData:(const void *)inputData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions;

@optional
- (void)audioFileStreamReadyToProducePackets:(SJAudioFileStream *)audioFileStream;

@end


@interface SJAudioFileStream : NSObject

@property (nonatomic, weak) id<SJAudioFileStreamDelegate> delegate;

@property (nonatomic, assign, readonly) AudioFileTypeID fileType;

@property (nonatomic, assign, readonly) BOOL available;

@property (nonatomic, assign, readonly) BOOL readyToProducePackets;

// 声音格式设置，这些设置要和采集时的配置一致
// struct AudioStreamBasicDescription
// {
//    Float64             mSampleRate;   // 采样率(立体声＝8000)
//    AudioFormatID       mFormatID;     // PCM格式
//    AudioFormatFlags    mFormatFlags;
//    UInt32              mBytesPerPacket;  // 数据包的字节数
//    UInt32              mFramesPerPacket; // 每个数据包中的采样帧数
//    UInt32              mBytesPerFrame;
//    UInt32              mChannelsPerFrame; // 1: 单声道；2：立体声
//    UInt32              mBitsPerChannel;   // 语音每采样点占用位数
//    UInt32              mReserved;
// };
@property (nonatomic, assign, readonly) AudioStreamBasicDescription format;

@property (nonatomic, assign, readonly) unsigned long long fileSize;

@property (nonatomic, assign, readonly) NSTimeInterval duration;

@property (nonatomic, assign, readonly) UInt32 bitRate;

@property (nonatomic, assign, readonly) UInt32 maxPacketSize;

@property (nonatomic, assign, readonly) UInt64 audioDataByteCount;

/// 初始化并打开 AudioFileStream
- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;

/// 解析音频数据
- (BOOL)parseData:(NSData *)data error:(NSError **)error;

/// 拖动到xx分xx秒
- (SInt64)seekToTime:(NSTimeInterval *)time;

/// 获取音频数据的 Magic Cookie
- (NSData *)getMagicCookieData;

/// 关闭 AudioFileStream
- (void)close;

@end
