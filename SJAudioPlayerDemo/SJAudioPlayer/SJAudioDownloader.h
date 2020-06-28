//
//  SJAudioDownloader.h
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/20.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SJAudioDownloader;

@protocol SJAudioDownloaderDelegate <NSObject>

- (void)downloader:(SJAudioDownloader *)downloader getAudioContentLength:(unsigned long long)contentLength;

- (void)downloader:(SJAudioDownloader *)downloader didReceiveData:(NSData *)data;

- (void)downloaderDidFinished:(SJAudioDownloader *)downloader;

- (void)downloaderErrorOccurred:(SJAudioDownloader *)downloader;

@end


@interface SJAudioDownloader : NSObject

+ (instancetype)downloadAudioWithURL:(NSURL *)url
                          byteOffset:(SInt64)byteOffset
                            delegate:(id<SJAudioDownloaderDelegate>)delegate;


- (void)cancelDownload;

@end

NS_ASSUME_NONNULL_END
