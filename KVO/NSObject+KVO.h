//
//  NSObject+KVO.h
//  KVO
//
//  Created by longhongwei on 16/5/11.
//  Copyright © 2016年 longhongwei. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^LWObservingBlock)(id observedObj,NSString *observedKey,id oldValue,id newValue);

@interface NSObject (KVO)

- (void)LW_addObserver:(NSObject *)observer
                forKey:(NSString *)key
             withBlock:(LWObservingBlock)block;

- (void)LW_removeObserver:(NSObject *)observer
                   forKey:(NSString *)key;

@end
