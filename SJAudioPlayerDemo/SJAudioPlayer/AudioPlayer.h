//
//  AudioPlayer.h
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2019/2/24.
//  Copyright © 2019年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SJAudioPlayerStatus)
{
    SJAudioPlayerStatusIdle     = 0,
    SJAudioPlayerStatusWaiting  = 1,
    SJAudioPlayerStatusPlaying  = 2,
    SJAudioPlayerStatusPaused   = 3,
    SJAudioPlayerStatusFinished = 4,
};


@class AudioPlayer;

@protocol SJAudioPlayerDelegate <NSObject>

@optional

- (void)audioPlayer:(AudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage;

- (void)audioPlayer:(AudioPlayer *)audioPlayer statusDidChanged:(SJAudioPlayerStatus)status;

@end


@interface AudioPlayer : NSObject

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

@end

NS_ASSUME_NONNULL_END
