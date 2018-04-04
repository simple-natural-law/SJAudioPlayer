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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSString *urlString = @"http://hoishow-file.b0.upaiyun.com/uploads/boom_track/file/4ba30881757c35365380dbe9c9538054_ab320.mp3";
//
//    NSString *escapedValue =
//    (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
//                                                                          nil,
//                                                                          (CFStringRef)urlString,
//                                                                          NULL,
//                                                                          NULL,
//                                                                          kCFStringEncodingUTF8));
    
    self.player = [[SJAudioPlayer alloc] initWithUrlString:urlString cachePath:nil];
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

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
