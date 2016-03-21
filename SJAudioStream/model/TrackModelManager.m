//
//  TrackModelManager.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "TrackModelManager.h"
#import "TrackModel.h"



//手动添加一个类目
@interface TrackModelManager ()

@property(nonatomic,retain)NSMutableArray *datasource;

@end



@implementation TrackModelManager

/**
 *  创建单利对象的方法
 *
 *  @return <#return value description#>
 */
+(instancetype)shareManager
{
    static TrackModelManager *manager=nil;
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        
        manager=[[TrackModelManager alloc]init];
        
    });
    
    return manager;
}




/**
 *  接收数据并且给model类赋值的过程
 */
-(void)receiveData:(SendDataBlock)sendDataBlock
{
    self.sendDataBlock = sendDataBlock;
    
    NSArray *contents=[NSArray arrayWithContentsOfURL:[NSURL URLWithString:@"http://project.lanou3g.com/teacher/UIAPI/MusicInfoList.plist"]];
    NSLog(@"contents=%@",contents);
    //先清空一下datasource
    [self.datasource removeAllObjects];
    
    for (NSDictionary *dic in contents)
    {
        TrackModel *track=[[TrackModel alloc] init];
        [track setValuesForKeysWithDictionary:dic];
        [self.datasource addObject:track];
    }
    
    self.sendDataBlock(self.datasource);
    
}



@end
