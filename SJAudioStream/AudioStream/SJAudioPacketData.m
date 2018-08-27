//
//  SJAudioPacketData.m
//  SJAudioStream
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioPacketData.h"

@interface SJAudioPacketData ()

@property (nonatomic, readwrite, strong) NSData *data;

@property (nonatomic, readwrite, assign) AudioStreamPacketDescription packetDescription;

@end

@implementation SJAudioPacketData


- (instancetype)initWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription
{
    if (bytes == NULL || packetDescription.mDataByteSize == 0)
    {
        return nil;
    }
    
    self = [super init];
    
    if (self)
    {
        self.data = [NSData dataWithBytes:bytes length:packetDescription.mDataByteSize];
        
        self.packetDescription = packetDescription;
    }
    return self;
}


@end
