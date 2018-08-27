//
//  SJAudioPacketData.h
//  SJAudioStream
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface SJAudioPacketData : NSObject

@property (nonatomic, readonly, strong) NSData *data;

@property (nonatomic, readonly, assign) AudioStreamPacketDescription packetDescription;

- (instancetype)initWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription;

@end
