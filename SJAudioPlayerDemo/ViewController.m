//
//  ViewController.m
//  SJAudioStream
//
//  Created by 讯心科技 on 2018/4/3.
//  Copyright © 2018年 讯心科技. All rights reserved.
//

#import "ViewController.h"
#import "SJAudioPlayer.h"


@interface ViewController ()<SJAudioPlayerDelegate>

@property (nonatomic, strong) SJAudioPlayer *player;

@property (weak, nonatomic) IBOutlet UIProgressView *progress;

@property (weak, nonatomic) IBOutlet UISlider *slider;

@property (weak, nonatomic) IBOutlet UILabel *durationLabel;

@property (weak, nonatomic) IBOutlet UILabel *progressLabel;

@end


@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSString *urlString = @"http://music.163.com/song/media/outer/url?id=166321.mp3";

    //NSString *urlString = @"http://music.163.com/song/media/outer/url?id=166317.mp3";
    
    NSURL *url = [NSURL URLWithString:urlString];
    
    //NSString *path = [[NSBundle mainBundle] pathForResource:@"MP3Sample" ofType:@"mp3"];

    //NSURL *url = [NSURL fileURLWithPath:path];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)updateProgress
{
    int duration = floor(self.player.duration);
    int progress = ceil(self.player.progress);
    
    self.durationLabel.text = [NSString stringWithFormat:@"%d",duration];
    self.progressLabel.text = [NSString stringWithFormat:@"%d",progress];
    
    if (self.player.duration > 0.0)
    {
        self.slider.value = self.player.progress/self.player.duration;
    }else
    {
        self.slider.value = 0.0;
    }
}

- (IBAction)play:(id)sender
{
    [self.player play];
}

- (IBAction)pause:(id)sender
{
    [self.player pause];
}

- (IBAction)stop:(id)sender
{
    [self.player stop];
}

- (IBAction)seek:(UISlider *)sender
{
    [self.player seekToProgress:(sender.value * self.player.duration)];
}


- (void)audioPlayer:(SJAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage
{
    self.progress.progress = percentage;
}

- (void)audioPlayer:(SJAudioPlayer *)audioPlayer didChangedStatus:(SJAudioPlayerStatus)status
{
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
