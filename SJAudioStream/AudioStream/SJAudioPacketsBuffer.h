//
//  SJAudioPacketsBuffer.h
//  SJAudioStream
//
//  Created by 张诗健 on 2017/11/27.
//  Copyright © 2017年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>


@class SJAudioPacketData;

@interface SJAudioPacketsBuffer : NSObject

+ (instancetype)buffer;

- (void)enqueueData:(SJAudioPacketData *)data;

- (BOOL)hasData;

- (UInt32)bufferedSize;

- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions;

- (void)clean;

@end
