//
//  ViewController.m
//  KVO
//
//  Created by longhongwei on 16/5/11.
//  Copyright © 2016年 longhongwei. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+KVO.h"

@interface Message : NSObject

@property (nonatomic, copy) NSString *text;

@end
@implementation Message

@end

@interface ViewController ()

@property (nonatomic, strong) Message *message;

@end

@implementation ViewController
- (IBAction)hhgd:(id)sender {
    self.message.text = @"new";
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.message = [[Message alloc] init];
    [self.message LW_addObserver:self forKey:NSStringFromSelector(@selector(text))
                       withBlock:^(id observedObject, NSString *observedKey, id oldValue, id newValue) {
//                           NSLog(@"%@.%@ is now: %@", observedObject, observedKey, newValue);
//                           dispatch_async(dispatch_get_main_queue(), ^{
//                               self.textfield.text = newValue;
//                           });
                           
                       }];
    

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
