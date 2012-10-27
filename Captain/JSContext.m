//
//  JSContext.m
//  JavascriptDemo
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JavaScriptCore.h"
#import "JSContext.h"

NSString* NSStringWithJSString(JSStringRef string);
NSString* NSStringWithJSValue(JSContextRef context, JSValueRef value);
NSDictionary* NSDictionaryWithJSObject(JSContextRef context, JSObjectRef object);
NSObject* NSObjectWithJSValue(JSContextRef context, JSValueRef value);
JSValueRef JSValueWithNSObject(JSContextRef context, id value, JSValueRef* exception);
JSStringRef JSStringCreateWithNSString(NSString* string);
JSObjectRef JSObjectWithNSDictionary(JSContextRef context, NSDictionary* dictionary);
JSValueRef JSValueWithNSString(JSContextRef context, NSString* string);
JSObjectRef JSObjectWithFunctionBlock(JSContextRef context, JSExtensionFunction function);

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
    
    if ([internalObject respondsToSelector:getterSelector]) {
        return YES;
    } else {
        // It's possible it has a method for it
        SEL methodCallSelector = MethodCallSelectorForName(key);
        return [internalObject respondsToSelector:methodCallSelector];
    }
}

// Attempts to call setValue:forKey: on a native object given a
// property name and a value to set.
bool NativeObjectSetProperty (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value, JSValueRef* exception) {
    
    id internalObject = (__bridge id)(JSObjectGetPrivate(object));
    
    NSString* key = NSStringWithJSString(propertyName);
    
    SEL setterSelector = PropertySetterSelectorForName(key);
    
    if ([internalObject respondsToSelector:setterSelector]) {
        NSObject* objectValue = NSObjectWithJSValue(ctx, value);
        
        [internalObject setValue:objectValue forKey:key];
        
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
    
    id internalObject = (__bridge id)(JSObjectGetPrivate(object));
    
    NSString* key = NSStringWithJSString(propertyName);
    
    SEL getterSelector = NSSelectorFromString(key);
    
    if ([internalObject respondsToSelector:getterSelector]) {
        
        id value = [internalObject valueForKey:key];
        
        return JSValueWithNSObject(ctx, value, exception);
    } else {
        
        // Could be a method call; if so, return a method call block object that wraps the call
        SEL methodCallSelector = MethodCallSelectorForName(key);
        
        if ([internalObject respondsToSelector:methodCallSelector]) {
            return (JSValueRef)JSObjectWithFunctionBlock(ctx, ^id(NSArray *parameters) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                return [internalObject performSelector:methodCallSelector withObject:parameters];                
#pragma clang diagnostic pop
            });
        }
        
        *exception  = JSValueWithNSString(ctx, [NSString stringWithFormat:@"%@ has no setter method '%@'", [internalObject class], key]);
        return JSValueMakeUndefined(ctx);
    }
}

// Cleans up dangling references to the internal Objective-C object
// stored inside a native object.
void NativeObjectFinalise (JSObjectRef object) {
    // The JSObject is going away;
    // Transfer the block object back into ARC, and then set it to nil;
    // this releases the block from memory
    id internalObject = CFBridgingRelease(JSObjectGetPrivate(object));
    internalObject = nil;
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
    JSExtensionFunction function = CFBridgingRelease(JSObjectGetPrivate(object));
    function = nil;    
}

// Called when a block function object gets called from JavaScript.
// Unpacks the parameters that were passed in from JS, and
// calls the block object.
JSValueRef BlockFunctionCallAsFunction (JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
    
    // Get the block object and call it; it stays managed by
    // the JSObject
    JSExtensionFunction functionBlock = (__bridge JSExtensionFunction)(JSObjectGetPrivate(function));
    
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
    
    // TODO: complete this
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
JSObjectRef JSObjectWithFunctionBlock(JSContextRef context, JSExtensionFunction function) {
    JSObjectRef functionObject = JSObjectMake(context, BlockFunctionClass(), (void*)CFBridgingRetain([function copy]));
    return functionObject;
}


@implementation JSContext {
    JSGlobalContextRef _scriptContext;
}

- (id)init
{
    self = [super init];
    if (self) {
        _scriptContext = JSGlobalContextCreate(NULL);
        
        // Register a simple 'log' method
        [self addFunction:^id(NSArray *parameters) {
            if (parameters.count > 0)
                NSLog(@"%@", [parameters objectAtIndex:0]);
            
            return nil;
        } withName:@"log"];
    }
    return self;
}

// Runs a script, using 'thisObject' as the value for the
// 'this' variable. Returns an NSObject representation
// of whatever the script evaluated to.
- (id) evaluateScript:(NSString *)script error:(NSError *__autoreleasing *)error thisObject:(JSObjectRef)thisObject {
    
    JSStringRef scriptJSString = JSStringCreateWithCFString((__bridge CFStringRef)(script));
    
    JSValueRef exception = nil;
    JSValueRef returnValue;
    
    returnValue = JSEvaluateScript(_scriptContext, scriptJSString, thisObject, NULL, 0, &exception);
    
    JSStringRelease(scriptJSString);
    
    if (exception != nil) {
        if (error != NULL) {
            NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
        
        return nil;
    }
    
    id objectValue = NSObjectWithJSValue(_scriptContext, returnValue);
    
    if ([objectValue isKindOfClass:[NSError class]]) {
        if (error != nil)
            *error = objectValue;
        
        return nil;
    }
    
    return objectValue;

}

// Runs a script, using the global object as the 'this' variable.
- (id)evaluateScript:(NSString *)script error:(NSError *__autoreleasing *)error {
    return [self evaluateScript:script error:error thisObject:NULL];
}


// Adds a function to an object, given a function block.
- (void) addFunction:(JSExtensionFunction)function withName:(NSString *)functionName inObject:(JSObjectRef)object {
    
    JSObjectRef functionObject;
    functionObject = JSObjectWithFunctionBlock(_scriptContext, function);
    
    JSStringRef functionNameJSString = JSStringCreateWithCFString((__bridge CFStringRef)(functionName));
    
    JSObjectSetProperty(_scriptContext, object, functionNameJSString, functionObject, kJSPropertyAttributeReadOnly, NULL);
    
    JSStringRelease(functionNameJSString);
}

// Adds a function to the global namespace, given a function block.
- (void) addFunction:(JSExtensionFunction)function withName:(NSString*)functionName {
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    
    [self addFunction:function withName:functionName inObject:globalObject];
    
}

// Adds a dictionary of named functions to a new object named
// 'functionDictionaryName', given a dictionary of key-value pairs,
// where the key is the name of the function and the value
// is a function block.
- (void) addFunctionsWithDictionary:(NSDictionary*)functionDictionary withName:(NSString*)functionDictionaryName {
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    JSObjectRef dictionaryObject = JSObjectMake(_scriptContext, NULL, NULL);
    
    [functionDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self addFunction:obj withName:key inObject:dictionaryObject];
    }];
    
    JSStringRef propertyName = JSStringCreateWithNSString(functionDictionaryName);
    
    JSObjectSetProperty(_scriptContext, globalObject, propertyName, dictionaryObject, kJSPropertyAttributeReadOnly, NULL);
    
    JSStringRelease(propertyName);
    
}

// Sets a property named 'propertyName' to the provided value
// in the global object.
- (void)setProperty:(NSString*)propertyName toObject:(id)object {
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    JSStringRef propertyNameJSString = JSStringCreateWithNSString(propertyName);
    
    JSValueRef objectValue = JSValueWithNSObject(_scriptContext, object, NULL);
    
    JSObjectSetProperty(_scriptContext, globalObject, propertyNameJSString, objectValue, 0, NULL);
    
    JSStringRelease(propertyNameJSString);
}

// Calls a function with the given name, using the provided
// parameters and the provided object as the 'this' variable.
// 'functionName' is evaluated, and can therefore be
// a complex dereference ('foo.bar.bas().functionName()').
- (id) callFunction:(NSString*)functionName withParameters:(NSArray*)parameters object:(NSObject*)thisObject error:(NSError**)error {
    
    JSValueRef exception = nil;
    
    // Evaluate which object this function name is referring to
    JSStringRef functionNameJSString = JSStringCreateWithNSString(functionName);
    JSValueRef evaluatedValue = JSEvaluateScript(_scriptContext, functionNameJSString, NULL, NULL, 0, &exception);
    
    JSStringRelease(functionNameJSString);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    // We have the value that it evaluated to; now we need to
    // if figure out if it's a callable object.
    
    JSObjectRef object = JSValueToObject(_scriptContext, evaluatedValue, &exception);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    if (JSObjectIsFunction(_scriptContext, object) == NO) {
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Object is not callable"}];
        return nil;
    }
    
    // Ok, we now know that the name we were passed in evaluates to a callable object. We'll now prepare the array of arguments and actually make the call.
    
    JSValueRef arguments[parameters.count];
    for (int argument = 0; argument < parameters.count; argument++) {
        id argumentAsObject = [parameters objectAtIndex:argument];
        JSValueRef argumentAsValue = JSValueWithNSObject(_scriptContext, argumentAsObject, &exception);
        
        if (exception != nil) {
            NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
            return nil;
        }
        
        arguments[argument] = argumentAsValue;
    }
    
    // It's callable; we'll now set up the object to use as the
    // 'this' object in the context of the function.
    
    JSValueRef thisObjectValue = JSValueWithNSObject(_scriptContext, thisObject, &exception);
    JSObjectRef thisObjectReference = JSValueToObject(_scriptContext, thisObjectValue, &exception);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    // Finally, call the function and return its value.
    JSValueRef returnValue = JSObjectCallAsFunction(_scriptContext, object, thisObjectReference, parameters.count, arguments, &exception);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    return NSObjectWithJSValue(_scriptContext, returnValue);;
}

// Loads a script, creating an object with the name taken from
// 'fileName' that's used as the 'this' object.
// This method first looks in the Documents directory for
// the appropriate JavaScript file before falling back to any
// built-in JavaScript files.
- (void)loadScriptNamed:(NSString*)fileName error:(NSError**)error  {
    
    NSURL* scriptURL = nil;
    
#if TARGET_OS_IPHONE
    // If we're running on the iPhone, look for the file in the
    // Documents folder first.
    NSURL* documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    
    scriptURL = [documentsURL URLByAppendingPathComponent:fileName];
    scriptURL = [scriptURL URLByAppendingPathExtension:@"js"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[scriptURL path]] == NO)
        scriptURL = nil;    
#endif
    
    // Else fall back to the built-in resources.
    if (scriptURL == nil) {
        scriptURL = [[NSBundle bundleForClass:[self class]] URLForResource:fileName withExtension:@"js"];
    }
    
    // Still couldn't find it? Give up.
    if (scriptURL == nil) {
        return;
    }
    
    // Load the script and evaluate it.
    NSString* scriptText = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:error];
    
    if (scriptText == nil)
        return;
    
    JSStringRef scriptNameJSString = JSStringCreateWithNSString(fileName);
    
    // Create an object to use that any variables will go into
    JSObjectRef object = JSObjectMake(_scriptContext, NULL, NULL);
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    JSObjectSetProperty(_scriptContext, globalObject, scriptNameJSString, object, 0, NULL);
    
    JSStringRelease(scriptNameJSString);
    
    [self evaluateScript:scriptText error:error thisObject:object];
}

// Tidy up the script execution context.
- (void)dealloc {
    JSGlobalContextRelease(_scriptContext);
}

@end
