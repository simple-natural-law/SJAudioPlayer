//
//  SJAudioFileStream.h
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/14.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "SJParsedAudioData.h"

@class SJAudioFileStream;

@protocol SJAudioFileStreamDelegate <NSObject>

@required
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData;

@optional
- (void)audioFileStreamReadyToProducePackets:(SJAudioFileStream *)audioFileStream;




@end


#define kDefaultBufferSize 2048

@interface SJAudioFileStream : NSObject

@property (nonatomic, assign) id<SJAudioFileStreamDelegate> delegate;

/*
 文件类型的提示，这个参数来帮助AudioFileStream对文件格式进行解析。这个参数在文件信息不完整（例如信息有缺陷）时尤其有用，它可以给与AudioFileStream一定的提示，帮助其绕过文件中的错误或者缺失从而成功解析文件。所以在确定文件类型的情况下建议各位还是填上这个参数，如果无法确定可以传入0
 */
@property (nonatomic,assign,readonly) AudioFileTypeID fileType;
@property (nonatomic,assign,readonly) BOOL available;
@property (nonatomic,assign,readonly) BOOL readyToProducePackets;


/*
 struct AudioStreamBasicDescription
 {
 Float64             mSampleRate; // 采样率(立体声＝8000)
 AudioFormatID       mFormatID;    // PCM格式
 AudioFormatFlags    mFormatFlags;
 UInt32              mBytesPerPacket; // 数据包的字节数
 UInt32              mFramesPerPacket; // 每个数据包中的采样帧数
 UInt32              mBytesPerFrame;
 UInt32              mChannelsPerFrame; // 1: 单声道；2：立体声
 UInt32              mBitsPerChannel;  // 语音每采样点占用位数
 UInt32              mReserved;
 };
 */
@property (nonatomic,assign,readonly) AudioStreamBasicDescription format; // 声音格式设置，这些设置要和采集时的配置一致
@property (nonatomic,assign,readonly) unsigned long long fileSize;
@property (nonatomic,assign,readonly) NSTimeInterval duration;
@property (nonatomic,assign,readonly) UInt32 bitRate;
@property (nonatomic,assign,readonly) UInt32 maxPacketSize;
@property (nonatomic,assign,readonly) UInt64 audioDataByteCount;

- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;

- (BOOL)parseData:(NSData *)data error:(NSError **)error;

/**
 *  seek to timeinterval
 *
 *  @param time On input, timeinterval to seek.
 On output, fixed timeinterval.
 *
 *  @return seek byte offset
 */
- (SInt64)seekToTime:(NSTimeInterval *)time;

- (NSData *)fetchMagicCookie;

- (void)close;

@end
