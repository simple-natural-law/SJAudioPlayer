//
//  SJTabBarViewController.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJTabBarViewController.h"
#import "SJMusicPlayerBar.h"
#import "UIView+LoadNib.h"
#import "SJHeaderFile.h"


@interface SJTabBarViewController ()

@property (nonatomic, strong) SJMusicPlayerBar *playBar;

@end

@implementation SJTabBarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    
    [self setUpPlayBar];
}


- (void)setUpPlayBar
{
    self.playBar = [SJMusicPlayerBar loadFromNibNoOwner];
    self.playBar.frame = CGRectMake(0, kScreenHeight - 64, kScreenWidth, 64);
    
    [self.view addSubview:self.playBar];
}




- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
