//
//  UIView+LoadNib.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/1/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "UIView+LoadNib.h"

@implementation UIView (LoadNib)


+ (id)loadFromNibNoOwner {
    UIView *result = nil;
    NSArray* elements = [[NSBundle mainBundle] loadNibNamed: NSStringFromClass([self class]) owner: nil options: nil];
    for (id anObject in elements) {
        if ([anObject isKindOfClass:[self class]]) {
            result = anObject;
            break;
        }
    }
    return result;
}



@end
