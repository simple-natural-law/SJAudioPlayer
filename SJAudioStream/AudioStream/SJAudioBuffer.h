//
//  SJAudioBuffer.h
//  AudioStreamDemo
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "SJParsedAudioData.h"

@interface SJAudioBuffer : NSObject

+ (instancetype)buffer;

- (void)enqueueData:(SJParsedAudioData *)data;
- (void)enqueueFromDataArray:(NSArray *)dataArray;

- (BOOL)hasData;

- (UInt32)bufferedSize;

//description needs free
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions;

- (void)clean;

@end
