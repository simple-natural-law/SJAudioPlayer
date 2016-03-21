//
//  TrackModel.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TrackModel : NSObject

@property (nonatomic, retain) NSString *mp3Url;


//因为id为关键字所以这里用identifier代替id
//@property (nonatomic, retain) NSNumber *identifier;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *picUrl;
@property (nonatomic, retain) NSString *blurPicUrl;
@property (nonatomic, retain) NSString *album;
@property (nonatomic, retain) NSString *singer;
@property (nonatomic, retain) NSNumber *duration;
@property (nonatomic, retain) NSString *artists_name;
@property (nonatomic, retain) NSString *lyric;
//@property (nonatomic, retain) NSString *artists;

@end
