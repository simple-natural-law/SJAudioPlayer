//
//  ZZAudioPlayer.h
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/22.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSUInteger, ZZAudioPlayerStatus)
{
    ZZAudioPlayerStatusIdle     = 0,
    ZZAudioPlayerStatusWaiting  = 1,
    ZZAudioPlayerStatusPlaying  = 2,
    ZZAudioPlayerStatusPaused   = 3,
    ZZAudioPlayerStatusFinished = 4,
    ZZAudioPlayerStatusError    = 5
};


typedef NS_ENUM(NSUInteger, ZZAudioPlayerError)
{
    ZZAudioPlayerDownloaderError = 0,
    ZZAudioPlayerDecoderError = 1,
    ZZAudioPlayerAudioQueueError = 2
};


@class ZZAudioPlayer;

@protocol ZZAudioPlayerDelegate <NSObject>

- (void)audioPlayer:(ZZAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage;

- (void)audioPlayer:(ZZAudioPlayer *)audioPlayer statusDidChanged:(ZZAudioPlayerStatus)status;

- (void)audioPlayer:(ZZAudioPlayer *)audioPlayer errorOccurred:(NSError *)error;

@end


@interface ZZAudioPlayer : NSObject

@property (nonatomic, readonly, strong) NSURL *url;

@property (nonatomic, readonly, assign) NSTimeInterval duration;

@property (nonatomic, readonly, assign) NSTimeInterval progress;

@property (nonatomic, readonly, assign) ZZAudioPlayerStatus status;

- (instancetype)initWithUrl:(NSURL *)url delegate:(id<ZZAudioPlayerDelegate>)delegate;

- (void)play;

- (void)pause;

- (void)seekToProgress:(NSTimeInterval)progress;

- (void)stop;

- (BOOL)isPlaying;

// playRate是0.5~2.0之间的值，默认为1.0。
- (void)setAudioPlayRate:(float)playRate;

@end

NS_ASSUME_NONNULL_END
