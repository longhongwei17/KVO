//
//  NSObject+KVO.m
//  KVO
//
//  Created by longhongwei on 16/5/11.
//  Copyright © 2016年 longhongwei. All rights reserved.
//

#import "NSObject+KVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kLWKVOClassPrefix = @"LWKVOClassPrefix_";
static NSString * const kLWKVOAssociatedObservers = @"LWKVOAssociatedObservers";

// 辅助类
@interface LWObserverInfo:NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) LWObservingBlock block;

@end

@implementation LWObserverInfo

- (instancetype)initWithObserver:(NSObject *)observer
                             key:(NSString *)key
                           block:(LWObservingBlock)block
{
    self = [super init];
    if (self) {
        self.block = block;
        self.key = key;
        self.observer = observer;
    }
    return self;
}
@end

// 工具C函数


static NSArray *classMethodNames(Class cls)
{
    NSMutableArray *list = @[].mutableCopy;
    unsigned int count = 0;
    Method *methodList = class_copyMethodList(cls, &count);
    for (int index = 0; index < count; index++) {
        Method method = methodList[index];
        [list addObject:NSStringFromSelector(method_getName(method))];
    }
    free(methodList);
    return list;
}

static void printDescription(NSString *name , id obj)
{
    NSString *str = [NSString stringWithFormat:
                     @"%@: %@\n\tNSObject class %s\n\tRuntime class %s\n\timplements methods <%@>\n\n",
                     name,
                     obj,
                     class_getName([obj class]),
                     class_getName(object_getClass(obj)),
                     [classMethodNames(object_getClass(obj)) componentsJoinedByString:@", "]];
    printf("%s\n", [str UTF8String]);
}

static NSString * getterForSetter(NSString *setter)
{
    if (setter.length <= 0|| ![setter hasPrefix:@"set"]) {
        return nil;
    }
    NSRange range = NSMakeRange(3, setter.length -4);
    NSString *key = [setter substringWithRange:range];
    
    // 第一个字母 小写
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:firstLetter];
    return key;
}

static NSString * setterForGetter(NSString * getter)
{
    if (getter.length <= 0) return nil;
    
    NSString *firstLetter = [[getter substringToIndex:1] uppercaseString];
    NSString *leftLetters = [getter substringFromIndex:1];
    
    return [NSString stringWithFormat:@"set%@%@:",firstLetter,leftLetters];
}

// 重写setter方法
static void kvo_setter(id self, SEL _cmd, id newValue)
{
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    
    if (!getterName) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have setter %@",self , setterName];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
        return;
    }
    
    id oldValue = [self valueForKey:getterName];
    struct objc_super superclazz = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    
    void(*objc_msgSendSuperCasted)(void *, SEL,id) = (void *)objc_msgSendSuper;
    
    objc_msgSendSuperCasted(&superclazz,_cmd, newValue);
    
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)kLWKVOAssociatedObservers);
    
    for (LWObserverInfo *each in observers) {
        if ([each.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                each.block(self,getterName,oldValue,newValue);
            });
        }
    }
}

static Class kvo_class(id self ,SEL _cmd)
{
    return class_getSuperclass(object_getClass(self));
}

@implementation NSObject (KVO)

- (void)LW_addObserver:(NSObject *)observer
                forKey:(NSString *)key
             withBlock:(LWObservingBlock)block
{
    SEL setterSelector = NSSelectorFromString(setterForGetter(key));
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    if (!setterMethod) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have a setter for key %@", self, key];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        
        return;
    }
    
    Class clazz = object_getClass(self);
    NSString *clazzName = NSStringFromClass(clazz);
    
    // if not an KVO class yet
    if (![clazzName hasPrefix:kLWKVOClassPrefix]) {
        clazz = [self createKVOClassWithOrginalClassName:clazzName];
        object_setClass(self, clazz);
    }
    
    // add our kvo setter if this class (not superclasses) doesn't implement the setter?
    if (![self hasSelector:setterSelector]) {
        const char *types = method_getTypeEncoding(setterMethod);
        class_addMethod(clazz, setterSelector, (IMP)kvo_setter, types);
    }
    
    LWObserverInfo *info = [[LWObserverInfo alloc] initWithObserver:observer key:key block:block];
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(kLWKVOAssociatedObservers));
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void *)(kLWKVOAssociatedObservers), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:info];
}

- (void)LW_removeObserver:(NSObject *)observer forKey:(NSString *)key
{
    NSMutableArray* observers = objc_getAssociatedObject(self, (__bridge const void *)(kLWKVOAssociatedObservers));
    
    LWObserverInfo *infoToRemove;
    for (LWObserverInfo* info in observers) {
        if (info.observer == observer && [info.key isEqual:key]) {
            infoToRemove = info;
            break;
        }
    }
    
    [observers removeObject:infoToRemove];
}


// 根据 监听类  创建 kVOe
- (Class)createKVOClassWithOrginalClassName:(NSString *)originalClassName
{
    NSString *kvoClazzName = [kLWKVOClassPrefix stringByAppendingString:originalClassName];
    Class clazz = NSClassFromString(kvoClazzName);
    
    if (clazz) {
        return clazz;
    }
    
    // class doesn't exist yet, make it
    Class originalClazz = object_getClass(self);
    Class kvoClazz = objc_allocateClassPair(originalClazz, kvoClazzName.UTF8String, 0);
    
    // grab class method's signature so we can borrow it
    Method clazzMethod = class_getInstanceMethod(originalClazz, @selector(class));
    const char *types = method_getTypeEncoding(clazzMethod);
    class_addMethod(kvoClazz, @selector(class), (IMP)kvo_class, types);
    
    objc_registerClassPair(kvoClazz);
    
    return kvoClazz;
    
}

- (BOOL)hasSelector:(SEL)selector
{
    Class clazz = object_getClass(self);
    unsigned int methodCount = 0;
    Method* methodList = class_copyMethodList(clazz, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        SEL thisSelector = method_getName(methodList[i]);
        if (thisSelector == selector) {
            free(methodList);
            return YES;
        }
    }
    
    free(methodList);
    return NO;
}

@end
