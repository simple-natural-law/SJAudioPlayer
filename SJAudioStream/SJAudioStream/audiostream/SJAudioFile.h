//
//  SJAudioFile.h
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/14.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/*
  AudioFile介绍：
  用来创建、初始化音频文件；读写音频数据；对音频文件进行优化；读取和写入音频格式信息等等，功能十分强大，可见它不但可以用来支持音频播放，甚至可以用来生成音频文件。
 
  
 */





@interface SJAudioFile : NSObject

@property (nonatomic, copy, readonly) NSString *filePath;


/*
 文件类型的提示，这个参数来帮助AudioFileStream对文件格式进行解析。这个参数在文件信息不完整（例如信息有缺陷）时尤其有用，它可以给与AudioFileStream一定的提示，帮助其绕过文件中的错误或者缺失从而成功解析文件。所以在确定文件类型的情况下建议各位还是填上这个参数，如果无法确定可以传入0
 */
@property (nonatomic, assign, readonly) AudioFileTypeID fileType;

@property (nonatomic, assign, readonly) BOOL available;



/*
 struct AudioStreamBasicDescription
 {
 Float64             mSampleRate; // 采样率(立体声＝8000)
 AudioFormatID       mFormatID;    // PCM格式
 AudioFormatFlags    mFormatFlags;
 UInt32              mBytesPerPacket;
 UInt32              mFramesPerPacket;
 UInt32              mBytesPerFrame;
 UInt32              mChannelsPerFrame; // 1: 单声道；2：立体声
 UInt32              mBitsPerChannel;  // 语音每采样点占用位数
 UInt32              mReserved;
 };
 */
@property (nonatomic, assign, readonly) AudioStreamBasicDescription format; // 声音格式设置，这些设置要和采集时的配置一致

@property (nonatomic, assign, readonly) unsigned long long fileSize;

@property (nonatomic, assign, readonly) NSTimeInterval duration;

@property (nonatomic, assign, readonly) UInt32 bitRate;

@property (nonatomic, assign, readonly) UInt32 maxPacketSize;

@property (nonatomic, assign, readonly) UInt64 audioDataByteCount;


- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;

- (NSData *)fetchMagicCookie;

- (NSArray *)parseData:(BOOL *)isEof;

- (void)seekToTime:(NSTimeInterval)time;

- (void)close;

@end
