//
//  SJAudioPlayer.h
//  AudioStreamDemo
//
//  Created by 张诗健 on 16/1/5.
//  Copyright © 2016年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioFile.h>


typedef NS_ENUM(NSUInteger, SJAudioPlayerStatus)
{
    SJAudioPlayerStatusStopped = 0,
    SJAudioPlayerStatusPlaying = 1,
    SJAudioPlayerStatusWaiting = 2,
    SJAudioPlayerStatusPaused = 3,
    SJAudioPlayerStatusFlushing = 4,
};

@interface SJAudioPlayer : NSObject

@property (nonatomic, copy,readonly) NSURL *url;
@property (nonatomic, assign, readonly) AudioFileTypeID fileType;


@property (nonatomic,readonly) SJAudioPlayerStatus status;
@property (nonatomic,readonly) BOOL isPlayingOrWaiting;
@property (nonatomic,assign,readonly) BOOL failed;

@property (nonatomic,assign) NSTimeInterval progress;
@property (nonatomic,readonly) NSTimeInterval duration;

/*
  初始化方法
*/
- (instancetype)initWithUrl:(NSURL *)url fileType:(AudioFileTypeID)fileType;

- (void)play;

- (void)pause;

- (void)stop;

@end
