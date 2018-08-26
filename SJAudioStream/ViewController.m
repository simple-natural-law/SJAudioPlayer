//
//  ViewController.m
//  SJAudioStream
//
//  Created by 讯心科技 on 2018/4/3.
//  Copyright © 2018年 讯心科技. All rights reserved.
//

#import "ViewController.h"
#import "SJAudioPlayer.h"


@interface ViewController ()

@property (nonatomic, strong) SJAudioPlayer *player;

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
    
    self.player = [[SJAudioPlayer alloc] initWithUrlString:urlString cachePath:nil];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)updateProgress
{
    self.durationLabel.text = [NSString stringWithFormat:@"%f",self.player.duration];
    self.progressLabel.text = [NSString stringWithFormat:@"%f",self.player.playedTime];
    
    self.slider.value = self.player.playedTime/self.player.duration;
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
    
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
