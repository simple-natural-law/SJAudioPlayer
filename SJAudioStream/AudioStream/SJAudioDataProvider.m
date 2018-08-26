//
//  SJAudioDataProvider.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioDataProvider.h"
#import "SJAudioStream.h"



@interface SJAudioDataProvider ()

@property (nonatomic, strong) SJAudioStream *stream;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) NSString *cachePath;

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, readwrite, assign) NSUInteger startOffset;

@property (nonatomic, readwrite, assign) NSUInteger contentLength;

@end

@implementation SJAudioDataProvider

- (instancetype)initWithURL:(NSURL *)url cacheFilePath:(NSString *)cacheFilePath byteOffset:(SInt64)byteOffset
{
    self = [super init];
    
    if (self)
    {
        self.url = url;
        self.cachePath   = cacheFilePath;
        self.byteOffset  = byteOffset;
        self.startOffset = byteOffset;
    }
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error completed:(BOOL *)completed
{
    // 音频数据偏移量 大于 音频数据总长度时 返回nil
    if (self.contentLength && self.byteOffset >= self.contentLength)
    {
        return nil;
    }
    
    if (!self.stream && self.url)
    {
        self.stream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.byteOffset];
    }
    
    NSData *data = [self.stream readDataWithMaxLength:maxLength error:error completed:completed];
    
    return data;
}


- (NSUInteger)contentLength
{
    return self.stream.contentLength;
}


- (void)close
{
    [self.stream close];
}

@end
