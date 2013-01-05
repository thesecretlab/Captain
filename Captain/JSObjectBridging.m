//
//  JSObjectBridging.c
//  Captain
//
//  Created by Jon Manning on 27/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JSDefines.h"
#import "JSTypeConversion.h"
#import "JSObjectBridging.h"
#import "JSContext.h"

// Given a string 'name', returns a selector
// for a method 'handleName:'
SEL MethodCallSelectorForName(NSString* name) {
    NSString* capitalizedString = [name stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[name substringToIndex:1] capitalizedString]];
    
    NSString* setterSelectorName = [NSString stringWithFormat:@"handle%@:", capitalizedString];
    
    SEL setterSelector = NSSelectorFromString(setterSelectorName);
    
    return setterSelector;
}

// Given a string 'name', returns a selector
// for a method 'setName:'
SEL PropertySetterSelectorForName(NSString* name) {
    NSString* capitalizedString = [name stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[name substringToIndex:1] capitalizedString]];
    
    NSString* setterSelectorName = [NSString stringWithFormat:@"set%@:", capitalizedString];
    
    SEL setterSelector = NSSelectorFromString(setterSelectorName);
    
    return setterSelector;
}

// Returns YES if an Objective-C object has a property 'propertyName'.
// Determined by either the presence of a setter method 'propertyName',
// or a handler method 'handlePropertyName:'.
bool NativeObjectHasProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName) {
    id internalObject = (__bridge id)(JSObjectGetPrivate(object));
    
    NSString* key = NSStringWithJSString(propertyName);
    
    SEL getterSelector = NSSelectorFromString(key);
    
    if ([internalObject conformsToProtocol:@protocol(JSCallableObject)]) {
        id<JSCallableObject> callableObject = internalObject;
        
        if ([[callableObject handlersForScriptMethods] objectForKey:key])
            return YES;
    }
    
    if ([internalObject respondsToSelector:getterSelector]) {
        return YES;
    }
    
    // If it implements the objectForKey: method, try that
    if ([internalObject respondsToSelector:@selector(objectForKey:)]) {
        if ([internalObject objectForKey:key])
            return YES;
    }
    
    
    
    // It's possible it has a method for it
    SEL methodCallSelector = MethodCallSelectorForName(key);
    if ([internalObject respondsToSelector:methodCallSelector])
        return YES;
    
    // Could be that the object's associated script object, if it has one, has it
    JSObjectRef scriptObject = [internalObject scriptObject];
    
    if (scriptObject != nil) {
        return JSObjectHasProperty(ctx, scriptObject, propertyName);
    }
    
    return NO;
    
    
}

// Attempts to call setValue:forKey: on a native object given a
// property name and a value to set.
bool NativeObjectSetProperty (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value, JSValueRef* exception) {
    
    // Grab the Objective-C object
    id internalObject = (__bridge id)(JSObjectGetPrivate(object));
    
    // Check to see if the object has a 'setFoo' method with the property name
    
    NSString* key = NSStringWithJSString(propertyName);
    SEL setterSelector = PropertySetterSelectorForName(key);
    
    NSObject* objectValue = NSObjectWithJSValue(ctx, value);
    
    if ([internalObject respondsToSelector:setterSelector]) {
        
        
        [internalObject setValue:objectValue forKey:key];
        
        return YES;
    } else if ([internalObject respondsToSelector:@selector(setObject:forKey:)]) {
        
        [internalObject setObject:objectValue forKey:key];
        return YES;
        
    } else {
        *exception  = JSValueWithNSString(ctx, [NSString stringWithFormat:@"%@ has no setter method '%@'", [internalObject class], NSStringFromSelector(setterSelector)]);
        return NO;
    }
    
}

// Attempts to get the value of a native object given a property
// name. If a getter method for a property doesn't exist,
// checks to see if a handler method for the named property exists;
// if it does, returns a function object that calls the method.
JSValueRef NativeObjectGetProperty (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef* exception) {
    
    // Grab the Objective-C object out from the JSObject
    id internalObject = (__bridge id)(JSObjectGetPrivate(object));
    
    NSString* key = NSStringWithJSString(propertyName);
    
    // If this object is callable, does it provide a handler block for 'propertyName'?
    
    if ([internalObject conformsToProtocol:@protocol(JSCallableObject)]) {
        id<JSCallableObject> callableObject = internalObject;
        
        JSFunction handlerBlock = [[callableObject handlersForScriptMethods] objectForKey:key];
        
        if (handlerBlock) {
            return (JSValueRef)JSObjectWithFunctionBlock(ctx, ^id(NSArray *parameters) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                return handlerBlock(parameters);
#pragma clang diagnostic pop
            });
        }
        
    }
    
    // Does this object respond to objectForKey:, and does this return something?
    id returnedObjectForKey = nil;
    if ([internalObject respondsToSelector:@selector(objectForKey:)] && (returnedObjectForKey = [internalObject objectForKey:key])) {
        return  JSValueWithNSObject(ctx, returnedObjectForKey, exception);
    }
    
    // Does this object respond to the getter selector for 'propertyName'?
    SEL getterSelector = NSSelectorFromString(key);
    
    if ([internalObject respondsToSelector:getterSelector]) {
        
        id value = [internalObject valueForKey:key];
        
        return JSValueWithNSObject(ctx, value, exception);
    } else {
        
        // Could be intended as a method call - we'll check by seeing if the
        // object has a 'handleFoo' method. If so, we'll return a method call
        // block object that performs this method when called.
        
        SEL methodCallSelector = MethodCallSelectorForName(key);
        
        if ([internalObject respondsToSelector:methodCallSelector]) {
            return (JSValueRef)JSObjectWithFunctionBlock(ctx, ^id(NSArray *parameters) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                return [internalObject performSelector:methodCallSelector withObject:parameters];
#pragma clang diagnostic pop
            });
        }
        
        // Could be that the object's associated script object, if it has one, has it
        JSObjectRef scriptObject = [internalObject scriptObject];
        
        if (scriptObject != nil) {
            return JSObjectGetProperty(ctx, scriptObject, propertyName, exception);
        }
        
        // Nope, not found
        
        *exception  = JSValueWithNSString(ctx, [NSString stringWithFormat:@"%@ has no method '%@'", [internalObject class], key]);
        return JSValueMakeUndefined(ctx);
    }
}

// Cleans up dangling references to the internal Objective-C object
// stored inside a native object.
void NativeObjectFinalise (JSObjectRef object) {
    // The JSObject is going away; transfer the block object back into
    // ARC, and then set it to nil. This releases the block from memory
    CFBridgingRelease(JSObjectGetPrivate(object));
}

JSClassDefinition NativeObjectClassDefinition = {
    0, // version
    0, // attributes
    "NativeObject", // class name
    NULL, // parent class
    NULL, // static values
    NULL, // static functions
    NULL, // initialise callback
    &NativeObjectFinalise, // finalise callback
    &NativeObjectHasProperty, // has property callback
    &NativeObjectGetProperty, // get property callback
    &NativeObjectSetProperty, // set property callback
    NULL, // delete property callback
    NULL, // get property names callback
    NULL, // call as function callback
    NULL, // call as constructor callback
    NULL, // has instance callback
    NULL  // convert to type callback
};

// Cleans up dangling references to the internal Objective-C object
// stored inside a block function object.
void BlockFunctionFinalise (JSObjectRef object) {
    // The JSObject is going away;
    // Transfer the block object back into ARC, and then set it to nil;
    // this releases the block from memory
    CFBridgingRelease(JSObjectGetPrivate(object));
    
}

// Called when a block function object gets called from JavaScript.
// Unpacks the parameters that were passed in from JS, and
// calls the block object.
JSValueRef BlockFunctionCallAsFunction (JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
    
    // Get the block object and call it; it stays managed by
    // the JSObject
    JSFunction functionBlock = (__bridge JSFunction)(JSObjectGetPrivate(function));
    
    NSMutableArray* functionParameters = [NSMutableArray array];
    
    for (int arg = 0; arg < argumentCount; arg++) {
        [functionParameters addObject:NSObjectWithJSValue(ctx, arguments[arg])];
    }
    
    id returnValue = functionBlock(functionParameters);
    
    return JSValueWithNSObject(ctx, returnValue, exception);
}

JSClassDefinition BlockFunctionClassDefinition = {
    0, // version
    0, // attributes
    "BlockFunction", // class name
    NULL, // parent class
    NULL, // static values
    NULL, // static functions
    NULL, // initialise callback
    &BlockFunctionFinalise, // finalise callback
    NULL, // has property callback
    NULL, // get property callback
    NULL, // set property callback
    NULL, // delete property callback
    NULL, // get property names callback
    &BlockFunctionCallAsFunction, // call as function callback
    NULL, // call as constructor callback
    NULL, // has instance callback
    NULL // convert to type callback
};

// Lazy loading getter for the shared class definition for block
// function objects.
JSClassRef BlockFunctionClass() {
    static JSClassRef _class = nil;
    
    if (_class == nil)
        _class = JSClassCreate(&BlockFunctionClassDefinition);
    
    return _class;
}

// Lazy loading getter for the shared class definition for
// native objects.
JSClassRef NativeObjectClass() {
    static JSClassRef _class = nil;
    
    if (_class == nil)
        _class = JSClassCreate(&NativeObjectClassDefinition);
    
    return _class;
}

JSObjectRef PointValueConstructor (JSContextRef ctx, JSObjectRef constructor, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
    
    JSObjectRef object = JSObjectMake(ctx, PointValueClass(), nil);
    
    if (argumentCount >= 2) {
        JSStringRef propertyName;
        
        propertyName = JSStringCreateWithUTF8CString("x");
        JSObjectSetProperty(ctx, object, propertyName, arguments[0], kJSPropertyAttributeDontDelete, exception);
        JSStringRelease(propertyName);
        
        
        propertyName = JSStringCreateWithUTF8CString("y");
        JSObjectSetProperty(ctx, object, propertyName, arguments[1], kJSPropertyAttributeDontDelete, exception);
        JSStringRelease(propertyName);
        
    }
    
    return object;
    
}

JSClassDefinition PointValueClassDefinition = {
    0, // version
    0, // attributes
    "Point", // class name
    NULL, // parent class
    NULL, // static values
    NULL, // static functions
    NULL, // initialise callback
    NULL, // finalise callback
    NULL, // has property callback
    NULL, // get property callback
    NULL, // set property callback
    NULL, // delete property callback
    NULL, // get property names callback
    NULL, // call as function callback
    &PointValueConstructor, // call as constructor callback
    NULL, // has instance callback
    NULL // convert to type callback
};

JSClassRef PointValueClass() {
    static JSClassRef _class = nil;
    
    if (_class == nil)
        _class = JSClassCreate(&PointValueClassDefinition);
    
    return _class;
}
