//
//  SJHttpStream.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/28.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

// 请求超时时间
#define HTTP_REQUEST_TIMEOUT 60

@interface SJHttpStream : NSObject

/**
 *  音频数据总长度
 */
@property (nonatomic, assign) NSUInteger contentLength;


/**
 *  根据 URL 和 数据偏移量 创建请求
 */
- (instancetype)initWithURL:(NSURL *)url byteOffset:(NSUInteger)byteOffset;


/**
 *  读取指定长度的数据 返回读取数据是否完毕
 *
 *  param maxLength  最大返回数据长度
 *  param error      错误信息
 *  param completed  是否已读完
 *  return  data
 */
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error completed:(BOOL *)completed;

/**
 *  结束请求
 */
- (void)close;


@end
