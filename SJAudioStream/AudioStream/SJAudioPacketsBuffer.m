//
//  SJAudioPacketsBuffer.m
//  SJAudioStream
//
//  Created by 张诗健 on 2017/11/27.
//  Copyright © 2017年 张诗健. All rights reserved.
//

#import "SJAudioPacketsBuffer.h"
#import "SJAudioPacketData.h"


@interface SJAudioPacketsBuffer ()

@property (nonatomic, strong) NSMutableArray *packetArray;

@property (nonatomic, assign) UInt32 bufferedSize;

@property (nonatomic, strong) NSLock *lock;

@end


@implementation SJAudioPacketsBuffer

+ (instancetype)buffer
{
    return [[self alloc] init];
}

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        self.packetArray = [[NSMutableArray alloc] init];
        
        self.bufferedSize = 0;
        
        self.lock = [[NSLock alloc] init];
    }
    
    return self;
}

- (BOOL)hasData
{
    return self.packetArray.count > 0;
}


- (UInt32)bufferedSize
{
    return _bufferedSize;
}


// 把解析完成的数据存储到 bufferArray 中
- (void)enqueueData:(SJAudioPacketData *)data
{
    [self.packetArray addObject:data];
    
    self.bufferedSize += (UInt32)data.data.length;
}

// 从 bufferArray 中取出解析完成的数据使用
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions
{
    if (requestSize == 0 && self.packetArray.count == 0)
    {
        return nil;
    }
    SInt64 size = requestSize;
    int i = 0;
    for (i = 0; i < self.packetArray.count; ++i)
    {
        SJAudioPacketData *packet = self.packetArray[i];
        
        SInt64 dataLength = [packet.data length];
        
        if (size > dataLength)
        {
            size -= dataLength;
        }else
        {
            if (size < dataLength)
            {
                i--;
            }
            break;
        }
    }
    
    if (i < 0)
    {
        return nil;
    }
    
    UInt32 count = (i >= self.packetArray.count) ? (UInt32)self.packetArray.count : i + 1;
    
    *packetCount = count;
    
    if (count == 0)
    {
        return nil;
    }
    
    /* 例如 int **p ;
     解释：
     int *p;则p是一个指向int型的变量的地址， p是地址；
     *p指的是内容
     而int **p；p指的是一个地址，p放的是*p的地址， *p指的是存放int 的地址.
     */
    if (descriptions != NULL)
    {
        *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * count);
    }
    
    NSMutableData *retData = [[NSMutableData alloc] init];
    
    for (int j = 0; j < count; ++j)
    {
        SJAudioPacketData *block = self.packetArray[j];
        
        if (descriptions != NULL)
        {
            AudioStreamPacketDescription desc = block.packetDescription;
            desc.mStartOffset = [retData length];
            (*descriptions)[j] = desc;
        }
        
        [retData appendData:block.data];
    }
    
    NSRange removeRange = NSMakeRange(0, count);
    
    [self.packetArray removeObjectsInRange:removeRange];
    
    self.bufferedSize -= (UInt32)retData.length;
    
    return retData;
}


- (void)clean
{
    self.bufferedSize = 0;
    
    [self.packetArray removeAllObjects];
}

@end