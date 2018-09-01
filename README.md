# SJAudioPlayer


## 介绍

`SJAudioPlayer`是一个基于 AudioQueue 实现的音频流播放器。其支持播放本地音频文件和远程音频文件，并支持对打断音频事件和拔出耳机事件的处理。相较于系统提供的`AVPlayer`和`AVAudioPlayer`，`SJAudioPlayer`的 CPU 消耗更低。

`SJAudioPlayer`暂不支持将音频数据缓存到本地，其只是将音频数据下载并保存到内存缓存中，并在下载音频数据的同时，从内存缓存中读取数据并解析和播放音频数据。因此`SJAudioPlayer`暂时也还不适合播放数据量较大的远程音频文件，如果需要实现缓存，可以联系我，我会尽快完善。（要实现缓存，只需要将原先保存到内存缓存中的音频数据改为写入文件，然后从文件中读取数据就好，你完全可以在该项目源代码的基础之上改动少量代码来实现缓存需求。）

![IMG_1](https://github.com/zhangshijian/SJAudioPlayer/raw/master/Images/IMG_1.PNG)
![IMG_2](https://github.com/zhangshijian/SJAudioPlayer/raw/master/Images/IMG_2.PNG)
![IMG_3](https://github.com/zhangshijian/SJAudioPlayer/raw/master/Images/IMG_3.PNG)

## 使用

播放本地音频文件：
```
NSString *path = [[NSBundle mainBundle] pathForResource:@"Sample" ofType:@"mp3"];

NSURL *url = [NSURL fileURLWithPath:path];

SJAudioPlayer *player = [[SJAudioPlayer alloc] initWithUrl:url];

player.delegate = self;

[player play];
```

播放远程音频文件：
```
NSURL *url = [NSURL URLWithString:urlString];

SJAudioPlayer *player = [[SJAudioPlayer alloc] initWithUrl:url];

player.delegate = self;

[player play];
```

实现`SJAudioPlayerDelegate`协议方法来监听播放器状态：
```
- (void)audioPlayer:(SJAudioPlayer *)audioPlayer statusDidChanged:(SJAudioPlayerStatus)status
{

}
```

实现`SJAudioPlayerDelegate`协议方法来监听音频文件数据下载进度：
```
- (void)audioPlayer:(SJAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage
{

}
```
