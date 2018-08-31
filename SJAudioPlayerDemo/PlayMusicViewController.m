//
//  PlayMusicViewController.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2017/4/3.
//  Copyright © 2017年 张诗健. All rights reserved.
//

#import "PlayMusicViewController.h"
#import "SJAudioPlayer/SJAudioPlayer.h"


@interface PlayMusicViewController ()<SJAudioPlayerDelegate>

@property (nonatomic, strong) SJAudioPlayer *player;

@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@property (weak, nonatomic) IBOutlet UIImageView *musiceImageView;

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property (weak, nonatomic) IBOutlet UISlider *slider;

@property (weak, nonatomic) IBOutlet UILabel *playedTimeLabel;

@property (weak, nonatomic) IBOutlet UILabel *durationLabel;

@end


@implementation PlayMusicViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //NSString *urlString = @"http://music.163.com/song/media/outer/url?id=166321.mp3";

    //NSString *urlString = @"http://music.163.com/song/media/outer/url?id=166317.mp3";
    
    //NSURL *url = [NSURL URLWithString:urlString];
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Sample" ofType:@"mp3"];

    NSURL *url = [NSURL fileURLWithPath:path];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)updateProgress
{
    int duration = floor(self.player.duration);
    int progress = ceil(self.player.progress);
    
    self.durationLabel.text = [NSString stringWithFormat:@"%d",duration];
    self.playedTimeLabel.text = [NSString stringWithFormat:@"%d",progress];
    
    if (self.player.duration > 0.0)
    {
        self.slider.value = self.player.progress/self.player.duration;
    }else
    {
        self.slider.value = 0.0;
    }
}


- (IBAction)showMusicList:(id)sender
{
    
}


- (IBAction)likeTheMusic:(id)sender
{
    
}


- (IBAction)changePlaySequence:(id)sender
{
    
}


- (IBAction)lastMusic:(id)sender
{
    
}


- (IBAction)nextMusic:(id)sender
{
    
}


- (IBAction)playOrPause:(id)sender
{
    
}


- (IBAction)seek:(UISlider *)sender
{
    [self.player seekToProgress:(sender.value * self.player.duration)];
}


- (void)audioPlayer:(SJAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage
{
    self.progressView.progress = percentage;
}

- (void)audioPlayer:(SJAudioPlayer *)audioPlayer statusDidChanged:(SJAudioPlayerStatus)status
{
    switch (status)
    {
        case SJAudioPlayerStatusIdle:
        {
            NSLog(@"SJAudioPlayerStatusIdle");
        }
            break;
        case SJAudioPlayerStatusWaiting:
        {
            NSLog(@"SJAudioPlayerStatusWaiting");
        }
            break;
        case SJAudioPlayerStatusPlaying:
        {
            NSLog(@"SJAudioPlayerStatusPlaying");
        }
            break;
        case SJAudioPlayerStatusPaused:
        {
            NSLog(@"SJAudioPlayerStatusPaused");
        }
            break;
        case SJAudioPlayerStatusFinished:
        {
            NSLog(@"SJAudioPlayerStatusFinished");
        }
            break;
        default:
            break;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
