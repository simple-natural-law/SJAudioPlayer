//
//  SJAudioDecoder.h
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/22.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


NS_ASSUME_NONNULL_BEGIN


@class SJAudioDecoder;

@protocol SJAudioDecoderDelegate <NSObject>

- (void)audioDecoder:(SJAudioDecoder *)audioDecoder readyToProducePacketsAndGetMagicCookieData:(NSData *)magicCookieData;

- (void)audioDecoder:(SJAudioDecoder *)audioDecoder
    receiveInputData:(const void *)inputData
       numberOfBytes:(UInt32)numberOfBytes
     numberOfPackets:(UInt32)numberOfPackets
  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions;

@end



@interface SJAudioDecoder : NSObject

@property (nonatomic, assign, readonly) AudioStreamBasicDescription format;

@property (nonatomic, assign, readonly) NSTimeInterval duration;


+ (instancetype)startDecodeAudioWithAudioType:(NSString *)audioType
                           audioContentLength:(NSUInteger)audioContentLength
                                     delegate:(id<SJAudioDecoderDelegate>)delegate;



- (BOOL)parseAudioData:(NSData *)data;


- (SInt64)seekToTime:(NSTimeInterval *)time;


- (void)endDecode;

@end

NS_ASSUME_NONNULL_END
