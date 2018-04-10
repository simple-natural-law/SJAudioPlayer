//
//  SJAudioPlayer.h
//  AudioTest
//
//  Created by 张诗健 on 16/4/29.
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
    SJAudioPlayerStatusStopped  = 5,
};



@interface SJAudioPlayer : NSObject

@property (nonatomic,readonly) NSString *urlString;

@property (nonatomic,readonly) NSUInteger contentLength;

@property (nonatomic,readonly) NSTimeInterval duration;

@property (nonatomic,readonly) SJAudioPlayerStatus status;



- (instancetype)initWithUrlString:(NSString *)url cachePath:(NSString *)cachePath;

- (void)play;

- (void)pause;

- (void)seekToProgress:(NSTimeInterval)timeOffset;

- (void)stop;

@end
