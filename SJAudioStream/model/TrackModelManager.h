//
//  TrackModelManager.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^SendDataBlock)(NSMutableArray *dataArr);

@interface TrackModelManager : NSObject

@property (nonatomic, copy) SendDataBlock sendDataBlock;

+(instancetype)shareManager;

-(void)receiveData:(SendDataBlock)sendDataBlock;



@end
