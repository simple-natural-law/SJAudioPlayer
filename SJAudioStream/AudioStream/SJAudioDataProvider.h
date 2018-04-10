//
//  SJAudioDataProvider.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SJAudioDataProvider : NSObject

/*
 *  开始读取数据时的音频数据偏移量
 */
@property (nonatomic, readonly) NSUInteger startOffset;


/*
 *  音频数据总长度
 */
@property (nonatomic, readonly) NSUInteger contentLength;



/**
 *  初始化对象
 *
 *  @param url           URL
 *  @param cacheFilePath 缓存路径
 *  @param byteOffset    音频数据偏移(seek)
 *
 *  @return SJAudioDataProvider
 */
- (instancetype)initWithURL:(NSURL *)url cacheFilePath:(NSString *)cacheFilePath byteOffset:(SInt64)byteOffset;


/**
 *  读取音频数据
 *
 *  param maxLength 最大返回数据长度
 *  param error     错误信息
 *  param completed     是否已读完
 *  return data
 */
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error completed:(BOOL *)completed;


- (void)close;

@end
