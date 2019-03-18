# SJAudioPlayer


## 介绍

`SJAudioPlayer`是一个基于 Audio Queue 实现的音频流播放器，相较于系统提供的`AVPlayer`和`AVAudioPlayer`，使用`SJAudioPlayer`播放音频时，CPU 的消耗更低。`SJAudioPlayer`支持以下功能：
- 播放本地音频文件和远程音频文件；
- 缓存远程音频数据到本地；
- 倍速播放音频；
- 暂停播放音频时，音频音量淡出；
- 处理打断事件和拔出耳机事件；
- 监听远程音频数据的下载进度和播放状态的切换；


<img src="https://github.com/zhangshijian/SJAudioPlayer/raw/master/Images/IMG_1.PNG" width="375" height="667" />

## 使用

播放本地音频文件：
```
NSString *path = [[NSBundle mainBundle] pathForResource:@"Sample" ofType:@"mp3"];

NSURL *url = [NSURL fileURLWithPath:path];

SJAudioPlayer *player = [[SJAudioPlayer alloc] initWithUrl:url delegate:self];

[self.player setAudioPlayRate:1.0];

[player play];
```

播放远程音频文件：
```
NSURL *url = [NSURL URLWithString:urlString];

SJAudioPlayer *player = [[SJAudioPlayer alloc] initWithUrl:url delegate:self];

[self.player setAudioPlayRate:1.0];

[player play];
```

设置音频播放速率：
```
[self.player setAudioPlayRate:1.5];
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
