//
//  SJAudioPlayer.h
//  SJAudioPlayer
//
//  Created by 张诗健 on 16/12/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef NS_ENUM(NSUInteger, SJAudioPlayerStatus)
{
    SJAudioPlayerStatusIdle     = 0,
    SJAudioPlayerStatusWaiting  = 1,
    SJAudioPlayerStatusPlaying  = 2,
    SJAudioPlayerStatusPaused   = 3,
    SJAudioPlayerStatusFinished = 4,
};


@class SJAudioPlayer;

@protocol SJAudioPlayerDelegate <NSObject>

@optional

- (void)audioPlayer:(SJAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage;

- (void)audioPlayer:(SJAudioPlayer *)audioPlayer statusDidChanged:(SJAudioPlayerStatus)status;

@end


@interface SJAudioPlayer : NSObject

@property (nonatomic, readonly, strong) NSURL *url;

@property (nonatomic, readonly, assign) NSTimeInterval duration;

@property (nonatomic, readonly, assign) NSTimeInterval progress;

@property (nonatomic, readonly, assign) SJAudioPlayerStatus status;

- (instancetype)initWithUrl:(NSURL *)url delegate:(id<SJAudioPlayerDelegate>)delegate;

- (void)play;

- (void)pause;

- (void)seekToProgress:(NSTimeInterval)progress;

- (void)stop;

- (BOOL)isPlaying;

// playRate是0.5~2.0之间的值，默认为1.0。
- (void)setAudioPlayRate:(float)playRate;

@end
