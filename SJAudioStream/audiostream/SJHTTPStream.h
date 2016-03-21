//
//  SJHTTPStream.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/21.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol SJHTTPStreamDelegate <NSObject>

- (void)didReceiveHttpHeaders:(NSDictionary *)httpHeaders AndFileSize:(unsigned long long)fileSize;

- (void)startReceiveData:(NSData *)data AndLength:(CFIndex)length;


@end


@interface SJHTTPStream : NSObject

@property (nonatomic, assign) id<SJHTTPStreamDelegate> delegate;

- (instancetype)initWithURL:(NSURL *)url;

- (BOOL)openReadStream;

@end
