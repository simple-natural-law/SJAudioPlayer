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
{
@private
    NSMutableArray *_bufferBlockArray;
    UInt32 _bufferedSize;
}


@end


@implementation SJAudioBuffer

+ (instancetype)buffer
{
    return [[self alloc] init];
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        _bufferBlockArray = [[NSMutableArray alloc]init];
    }
    return self;
}

- (BOOL)hasData
{
    return _bufferBlockArray.count > 0;
}

- (UInt32)bufferedSize
{
    return _bufferedSize;
}


- (void)enqueueFromDataArray:(NSArray *)dataArray
{
    for (SJParsedAudioData *data in dataArray) {
        [self enqueueData:data];
    }
}

// 把解析完成的数据存储到 bufferArray 中
- (void)enqueueData:(SJParsedAudioData *)data
{
    if ([data isKindOfClass:[SJParsedAudioData class]]) {
        [_bufferBlockArray addObject:data];
        _bufferedSize += data.data.length;
    }
}

// 从 bufferArray 中取出解析完成的数据使用
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions
{
    if (requestSize == 0 && _bufferBlockArray.count == 0) {
        return nil;
    }
    SInt64 size = requestSize;
    int i = 0;
    for (i = 0; i < _bufferBlockArray.count; ++i) {
        SJParsedAudioData *block = _bufferBlockArray[i];
        SInt64 dataLength = [block.data length];
        if (size > dataLength) {
            size -= dataLength;
        }
        else
        {
            if (size < dataLength) {                                                                                     
                i--;
            }
            break;
        }
    }
    
    if (i < 0) {
        return nil;
    }
    
    UInt32 count = (i >= _bufferBlockArray.count) ? (UInt32)_bufferBlockArray.count : i + 1;
    
    *packetCount = count;
    
    if (count == 0) {
        return nil;
    }
    
    /* 例如 int **p ;
       解释：
       int *p;则p是一个指向int型的变量的地址， p是地址；
       *p指的是内容
       而int **p；p指的是一个地址，p放的是*p的地址， *p指的是存放int 的地址.
     */
    if (descriptions != NULL) {
        *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * count);
    }
    NSMutableData *retData = [[NSMutableData alloc] init];
    for (int j = 0; j < count; ++j) {
        SJParsedAudioData *block = _bufferBlockArray[j];
        if (descriptions != NULL) {
            AudioStreamPacketDescription desc = block.packetDescription;
            desc.mStartOffset = [retData length];
            (*descriptions)[j] = desc;
        }
        [retData appendData:block.data];
    }
    NSRange removeRange = NSMakeRange(0, count);
    [_bufferBlockArray removeObjectsInRange:removeRange];
    
    _bufferedSize -= retData.length;
    
    return retData;
}


- (void)clean
{
    _bufferedSize = 0;
    [_bufferBlockArray removeAllObjects];
}

#pragma -mark
- (void)dealloc
{
    [_bufferBlockArray removeAllObjects];
}

@end
