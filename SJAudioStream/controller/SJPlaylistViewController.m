//
//  SJPlaylistViewController.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJPlaylistViewController.h"
#import "TrackModel.h"
#import "TrackModelManager.h"
#import "SJAudioPlayer.h"
#import "ViewController.h"


@interface SJPlaylistViewController ()<UITableViewDataSource,UITableViewDelegate>

@property (nonatomic, strong) NSMutableArray *trackArr;

@end


@implementation SJPlaylistViewController

- (void)requestTracklistData
{
    NSArray *contents=[NSArray arrayWithContentsOfURL:[NSURL URLWithString:@"http://project.lanou3g.com/teacher/UIAPI/MusicInfoList.plist"]];
    
    for (NSDictionary *dic in contents)
    {
        TrackModel *track=[[TrackModel alloc] init];
        [track setValuesForKeysWithDictionary:dic];
        [self.trackArr addObject:track];
    }
    
    [self.tableView reloadData];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self requestTracklistData];
}


#pragma -mark delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.trackArr.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    
    if (cell == nil) {
        
        cell = [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    }
    
    TrackModel *track = self.trackArr[indexPath.row];
    
    cell.textLabel.text = track.name;
    
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    ViewController *vc = [[UIStoryboard storyboardWithName:@"Main" bundle:nil]instantiateViewControllerWithIdentifier:@"playController"];
    
    vc.currentTrack = self.trackArr[indexPath.row];
    
    [self.navigationController pushViewController:vc animated:YES];
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 40;
}




#pragma -mark
- (NSMutableArray *)trackArr
{
    if (!_trackArr) {
        _trackArr = [[NSMutableArray alloc]init];
    }
    return _trackArr;
}


@end
