//
//  SJAudioBuffer.m
//  AudioStreamDemo
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioBuffer.h"
#import "SJParsedAudioData.h"


@interface SJAudioBuffer ()

@property (nonatomic, strong) NSMutableArray *bufferBlockArray;

@property (nonatomic, assign) UInt32 bufferedSize;

@end


@implementation SJAudioBuffer

+ (instancetype)buffer
{
    return [[self alloc] init];
}


- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        self.bufferBlockArray = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)hasData
{
    return self.bufferBlockArray.count > 0;
}

- (UInt32)bufferedSize
{
    return _bufferedSize;
}


- (void)enqueueFromDataArray:(NSArray *)dataArray
{
    for (SJParsedAudioData *data in dataArray)
    {
        [self enqueueData:data];
    }
}

// 把解析完成的数据存储到 bufferArray 中
- (void)enqueueData:(SJParsedAudioData *)data
{
    if ([data isKindOfClass:[SJParsedAudioData class]])
    {
        [self.bufferBlockArray addObject:data];
        
        self.bufferedSize += (UInt32)data.data.length;
    }
}

// 从 bufferArray 中取出解析完成的数据使用
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions
{
    if (requestSize == 0 && self.bufferBlockArray.count == 0)
    {
        return nil;
    }
    SInt64 size = requestSize;
    int i = 0;
    for (i = 0; i < self.bufferBlockArray.count; ++i)
    {
        SJParsedAudioData *block = self.bufferBlockArray[i];
        
        SInt64 dataLength = [block.data length];
        
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
    
    UInt32 count = (i >= self.bufferBlockArray.count) ? (UInt32)self.bufferBlockArray.count : i + 1;
    
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
        SJParsedAudioData *block = self.bufferBlockArray[j];
        
        if (descriptions != NULL)
        {
            AudioStreamPacketDescription desc = block.packetDescription;
            desc.mStartOffset = [retData length];
            (*descriptions)[j] = desc;
        }
        
        [retData appendData:block.data];
    }
    
    NSRange removeRange = NSMakeRange(0, count);
    
    [self.bufferBlockArray removeObjectsInRange:removeRange];
    
    self.bufferedSize -= (UInt32)retData.length;
    
    return retData;
}


- (void)clean
{
    self.bufferedSize = 0;
    
    [self.bufferBlockArray removeAllObjects];
}

@end
