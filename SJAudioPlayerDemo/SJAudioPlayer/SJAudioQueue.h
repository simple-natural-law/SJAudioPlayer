//
//  SJAudioQueue.h
//  SJAudioPlayer
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


@interface SJAudioQueue : NSObject

@property (nonatomic, assign, readonly) BOOL available;

@property (nonatomic, assign, readonly) AudioStreamBasicDescription format;

@property (nonatomic, assign, readonly) BOOL isRuning;

@property (nonatomic, assign, readonly) NSTimeInterval playedTime;

@property (nonatomic, assign) float volume;

@property (nonatomic, assign) UInt32  bufferSize;


- (instancetype)initWithFormat:(AudioStreamBasicDescription)format bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie;

- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof;

- (void)pause:(BOOL)immediately;

- (BOOL)resume;

- (BOOL)stop:(BOOL)immediately;

- (BOOL)reset;

- (BOOL)flush;

- (void)disposeAudioQueue;

@end
