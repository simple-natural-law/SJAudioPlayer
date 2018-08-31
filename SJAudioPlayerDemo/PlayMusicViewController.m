//
//  PlayMusicViewController.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2017/4/3.
//  Copyright © 2017年 张诗健. All rights reserved.
//

#import "PlayMusicViewController.h"
#import "SJAudioPlayer/SJAudioPlayer.h"
#import "SDWebImage/UIImageView+WebCache.h"

@interface PlayMusicViewController ()<SJAudioPlayerDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@property (weak, nonatomic) IBOutlet UIImageView *musiceImageView;

@property (weak, nonatomic) IBOutlet UILabel *musicNameLabel;

@property (weak, nonatomic) IBOutlet UILabel *artistLabel;

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property (weak, nonatomic) IBOutlet UISlider *slider;

@property (weak, nonatomic) IBOutlet UILabel *playedTimeLabel;

@property (weak, nonatomic) IBOutlet UILabel *durationLabel;

@property (nonatomic, strong) SJAudioPlayer *player;

@property (nonatomic, strong) NSArray *musicList;

@property (nonatomic, strong) NSDictionary *currentMusicInfo;

@end


@implementation PlayMusicViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    
    //    NSString *path = [[NSBundle mainBundle] pathForResource:@"Sample" ofType:@"mp3"];
    
    //    NSURL *url = [NSURL fileURLWithPath:path];
    
    self.musicList = @[@{@"music_url":@"http://music.163.com/song/media/outer/url?id=166321.mp3", @"pic":@"http://imgsrc.baidu.com/forum/w=580/sign=0828c5ea79ec54e741ec1a1689399bfd/e3d9f2d3572c11df80fbf7f7612762d0f703c238.jpg", @"artist":@"毛阿敏", @"music_name":@"爱上张无忌"}];
    
    self.currentMusicInfo = self.musicList.firstObject;
    
    NSURL *url = [NSURL URLWithString:self.currentMusicInfo[@"music_url"]];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)updateProgress
{
    self.durationLabel.text = [self timeIntervalToMMSSFormat:self.player.duration];
    self.playedTimeLabel.text = [self timeIntervalToMMSSFormat:self.player.progress];
    
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


- (IBAction)likeTheMusic:(UIButton *)sender
{
    sender.selected = !sender.selected;
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


- (IBAction)playOrPause:(UIButton *)sender
{
    if ([self.player isPlaying])
    {
        [self.player pause];
        
        sender.selected = NO;
    }else
    {
        [self.player play];
        
        sender.selected = YES;
    }
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


- (void)setCurrentMusicInfo:(NSDictionary *)currentMusicInfo
{
    _currentMusicInfo = currentMusicInfo;
    
    __weak typeof(self) weakself = self;
    
    [self.musiceImageView sd_setImageWithURL:[NSURL URLWithString:currentMusicInfo[@"pic"]] placeholderImage:[UIImage imageNamed:@"music_placeholder"] completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        
        __strong typeof(weakself) strongself = weakself;
        
        strongself.backgroundImageView.image = image;
    }];
    
    self.musicNameLabel.text = currentMusicInfo[@"music_name"];
    
    self.artistLabel.text    = currentMusicInfo[@"artist"];
}


- (NSString *)timeIntervalToMMSSFormat:(NSTimeInterval)interval
{
    NSInteger ti = (NSInteger)interval;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
