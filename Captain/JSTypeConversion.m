//
//  JSTypeConversion.c
//  Captain
//
//  Created by Jon Manning on 27/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JavaScriptCore.h"
#import "JSTypeConversion.h"
#import "JSObjectBridging.h"

// Returns an NSString, given a JSString.
NSString* NSStringWithJSString(JSStringRef string) {
    CFStringRef stringAsCFString = JSStringCopyCFString(NULL, string);
    NSString* stringAsNSString = CFBridgingRelease(stringAsCFString);
    
    return stringAsNSString;
}

// Returns an NSString, given a JSValue.
// This is effectively the same behaviour as "someObject.toString()".
NSString* NSStringWithJSValue(JSContextRef context, JSValueRef value) {
    
    if (context == nil || value == nil)
        return nil;
    
    JSValueRef exception = nil;
    JSStringRef stringValue = JSValueToStringCopy(context, value, &exception);
    
    NSString* returnString = nil;
    
    if (exception != nil) {
        returnString = NSStringWithJSValue(context, value);
    } else {
        returnString = NSStringWithJSString(stringValue);
    }
    
    JSStringRelease(stringValue);
    
    return returnString;
}

// Returns an NSDictionary that matches the contents of a
// JavaScript object.
NSDictionary* NSDictionaryWithJSObject(JSContextRef context, JSObjectRef object) {
    
    JSPropertyNameArrayRef propertyNames = JSObjectCopyPropertyNames(context, object);
    
    size_t propertyCount = JSPropertyNameArrayGetCount(propertyNames);
    
    NSMutableDictionary* properties = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < propertyCount; i++) {
        JSStringRef propertyName = JSPropertyNameArrayGetNameAtIndex(propertyNames, i);
        
        NSString* key = NSStringWithJSString(propertyName);
        
        
        JSValueRef exception = nil;
        JSValueRef valueRef = JSObjectGetProperty(context, object, propertyName, &exception);
        
        if (exception != nil) {
            JSPropertyNameArrayRelease(propertyNames);
            return nil;
        }
        
        id value = NSObjectWithJSValue(context, valueRef);
        
        [properties setObject:value forKey:key];
    }
    
    return [NSDictionary dictionaryWithDictionary:properties];
    
}

id CallFunctionObject(JSContextRef context, JSObjectRef object, NSArray* parameters, id thisObject, JSObjectRef prototype, JSValueRef* exception) {
    
    // Build a C array containing the parameters, each converted to JSValueRefs.
    JSValueRef arguments[parameters.count];
    for (int argument = 0; argument < parameters.count; argument++) {
        id argumentAsObject = [parameters objectAtIndex:argument];
        JSValueRef argumentAsValue = JSValueWithNSObject(context, argumentAsObject, exception);
        
        if (exception != nil && *exception != nil) {
            return nil;
        }
        
        arguments[argument] = argumentAsValue;
    }
    
    // If we were given an object to use as 'this', use it (after wrapping it in a JSObjectRef);
    // otherwise, use the context's global object as 'this'.
    
    JSObjectRef thisObjectReference;
    
    if (thisObject == nil)
        thisObjectReference = JSContextGetGlobalObject(context);
    else
        thisObjectReference = JSObjectMake(context, NativeObjectClass(), (void*)CFBridgingRetain(thisObject));
    
    if (prototype != NULL)
        JSObjectSetPrototype(context, thisObjectReference, prototype);
    
    // Finally, call the function and return its value.
    JSValueRef returnValue = JSObjectCallAsFunction(context, object, thisObjectReference, parameters.count, arguments, exception);
    
    if (exception != nil && *exception != nil) {
        return nil;
    }
    
    // Convert the result back from a JSValueRef into an NSObject.
    return NSObjectWithJSValue(context, returnValue);
    
}

// Converts a JSValue to an equivalent NSObject type.
// Strings are converted to NSStrings, numbers to NSNumbers, etc.
NSObject* NSObjectWithJSValue(JSContextRef context, JSValueRef value) {
    
    JSValueRef exception = nil;
    
    id returnObjCValue;
    
    switch (JSValueGetType(context, value)) {
        case kJSTypeNull:
            returnObjCValue = [NSNull null];
            break;
        case kJSTypeBoolean:
            returnObjCValue = @(JSValueToBoolean(context, value));
            break;
        case kJSTypeNumber:
            returnObjCValue = @(JSValueToNumber(context, value, &exception));
            break;
        case kJSTypeObject:
            if (JSValueIsObjectOfClass(context, value, NativeObjectClass())) {
                return (__bridge id)JSObjectGetPrivate((JSObjectRef)value);
            } else if (JSValueIsObjectOfClass(context, value, BlockFunctionClass())) {
                return [NSString stringWithFormat:@"<Block Function %p>", JSObjectGetPrivate((JSObjectRef)value)];
            } else if (JSObjectIsFunction(context, (JSObjectRef)value)) {
                returnObjCValue = ^(NSArray* parameters) {
                    return CallFunctionObject(context, (JSObjectRef)value, parameters, nil, NULL, nil);
                };
            } else {
                returnObjCValue = NSDictionaryWithJSObject(context, (JSObjectRef)value);
            }
            break;
        case kJSTypeUndefined:
        case kJSTypeString:
            returnObjCValue = NSStringWithJSValue(context, value);
            break;
        default:
            break;
    }
    
    if (exception != nil) {
        NSError* error;
        NSString* errorString = NSStringWithJSValue(context, exception);
        error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        
        return  error;
    }
    
    return returnObjCValue;
}

// Returns a JSString created with an NSString. Ownership
// follows the create rule.
JSStringRef JSStringCreateWithNSString(NSString* string) {
    CFStringRef cfString = (__bridge CFStringRef)(string);
    JSStringRef jsString = JSStringCreateWithCFString(cfString);
    return jsString;
    
}

// Returns a JSValueRef containing a JSString, which has
// been created using an NSString. The memory is managed by
// the JavaScript context.
JSValueRef JSValueWithNSString(JSContextRef context, NSString* string) {
    JSStringRef jsString = JSStringCreateWithNSString(string);
    JSValueRef stringValue = JSValueMakeString(context, jsString);
    JSStringRelease(jsString);
    
    return stringValue;
}

// Returns a JSValueRef containing a representation of a
// native object. Primitive types (like strings and numbers)
// are converted to JavaScript-internal representations;
// other objects are wrapped as native objects.
JSValueRef JSValueWithNSObject(JSContextRef context, id value, JSValueRef* exception) {
    
    if (context == NULL) {
        return NULL;
    }
    
    // TODO: complete this for further types
    if ([value isKindOfClass:[NSNumber class]])
        return JSValueMakeNumber(context, [value doubleValue]);
    if ([value isKindOfClass:[NSString class]])
        return JSValueWithNSString(context, value);
    if ([value isKindOfClass:[NSNull class]] || value == nil)
        return JSValueMakeNull(context);
    
    // Wrap it in a wrapper object
    JSObjectRef wrapperObject = JSObjectMake(context, NativeObjectClass(), (void*)CFBridgingRetain(value));
    
    return wrapperObject;
    
}

// Returns a JSObjectRef containing a function block. This object
// is callable from JavaScript.
JSObjectRef JSObjectWithFunctionBlock(JSContextRef context, JSFunction function) {
    JSObjectRef functionObject = JSObjectMake(context, BlockFunctionClass(), (void*)CFBridgingRetain([function copy]));
    return functionObject;
}

