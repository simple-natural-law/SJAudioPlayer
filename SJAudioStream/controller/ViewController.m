//
//  ViewController.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/18.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "ViewController.h"
#import "SJAudioPlayer.h"
#import "TrackModel.h"

@interface ViewController ()
{
    SJAudioPlayer *_player;
    
    NSTimer *_progressTimer;
    
    NSTimer *_seekTimer;
    
    NSTimeInterval _seekToTime;

}

@property (weak, nonatomic) IBOutlet UISlider *slider;

@end



@implementation ViewController


- (IBAction)seek:(id)sender {
    
    UISlider *slider = sender;
    
    _seekToTime = slider.value * _player.duration;
    
    [_progressTimer setFireDate:[NSDate distantFuture]];
    
    [_seekTimer invalidate];
    
    _seekTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(doSeeking) userInfo:nil repeats:NO];

}

- (void)doSeeking
{
    [_player setProgress:_seekToTime];
    
    [_progressTimer setFireDate:[NSDate distantPast]];
}


- (IBAction)play:(id)sender {
    
    [_player play];
}


- (IBAction)pause:(id)sender {
    
    [_player pause];
}


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSString *urlString = @"http://hoishow-file.b0.upaiyun.com/uploads/boom_track/file/4ba30881757c35365380dbe9c9538054_ab320.mp3";
    
    NSString *escapedValue =
    (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
                                                                          nil,
                                                                          (CFStringRef)urlString,
                                                                          NULL,
                                                                          NULL,
                                                                          kCFStringEncodingUTF8));
    
    NSURL *url = [NSURL URLWithString:escapedValue];
    
    _player = [[SJAudioPlayer alloc]initWithUrl:url fileType:kAudioFileMP3Type];
    
    _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];

}



- (void)updateProgress
{
    self.slider.value = _player.progress / _player.duration;
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
