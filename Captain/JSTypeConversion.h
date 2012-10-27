//
//  JSTypeConversion.h
//  Captain
//
//  Created by Jon Manning on 27/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JSDefines.h"

NSString* NSStringWithJSString(JSStringRef string);
NSString* NSStringWithJSValue(JSContextRef context, JSValueRef value);
NSDictionary* NSDictionaryWithJSObject(JSContextRef context, JSObjectRef object);
NSObject* NSObjectWithJSValue(JSContextRef context, JSValueRef value);
JSValueRef JSValueWithNSObject(JSContextRef context, id value, JSValueRef* exception);
JSStringRef JSStringCreateWithNSString(NSString* string);
JSObjectRef JSObjectWithNSDictionary(JSContextRef context, NSDictionary* dictionary);
JSValueRef JSValueWithNSString(JSContextRef context, NSString* string);
JSObjectRef JSObjectWithFunctionBlock(JSContextRef context, JSFunction function);
id CallFunctionObject(JSContextRef context, JSObjectRef object, NSArray* parameters, id thisObject, JSValueRef* exception);

