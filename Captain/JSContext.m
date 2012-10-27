//
//  JSContext.m
//  JavascriptDemo
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JSContext.h"

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
            NSLog(@"%@", [parameters componentsJoinedByString:@" "]);
            
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
- (void) addFunction:(JSFunction)function withName:(NSString *)functionName inObject:(JSObjectRef)object {
    
    JSObjectRef functionObject;
    functionObject = JSObjectWithFunctionBlock(_scriptContext, function);
    
    JSStringRef functionNameJSString = JSStringCreateWithCFString((__bridge CFStringRef)(functionName));
    
    JSObjectSetProperty(_scriptContext, object, functionNameJSString, functionObject, kJSPropertyAttributeReadOnly, NULL);
    
    JSStringRelease(functionNameJSString);
}

// Adds a function to the global namespace, given a function block.
- (void) addFunction:(JSFunction)function withName:(NSString*)functionName {
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
- (id) callFunction:(NSString*)functionName withParameters:(NSArray*)parameters thisObject:(NSObject*)thisObject error:(NSError**)error {
    
    JSValueRef exception = nil;
    
    // Evaluate which object this function name is referring to
    JSStringRef functionNameJSString = JSStringCreateWithNSString(functionName);
    JSValueRef evaluatedValue = JSEvaluateScript(_scriptContext, functionNameJSString, NULL, NULL, 0, &exception);
    
    JSStringRelease(functionNameJSString);
    
    // Could we find it?
    if (exception != nil && error != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    // We have the value that it evaluated to; now we need to
    // if figure out if it's a callable object.
    
    
    // Is it an object?
    JSObjectRef object = JSValueToObject(_scriptContext, evaluatedValue, &exception);
    
    if (exception != nil && error != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    // Is it a _callable_ object?
    if (JSObjectIsFunction(_scriptContext, object) == NO && error != nil) {
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:@"Object is not callable"}];
        return nil;
    }
    
    // Ok, call it!
    id returnValue = CallFunctionObject(_scriptContext, object, parameters, thisObject, &exception);
    
    // Was there an exception?
    if (exception != nil && error != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        return nil;
    }
    
    // Finally, return the fruits of our labours.
    return returnValue;
}

// Loads a script, creating an object with the name taken from
// 'fileName' that's used as the 'this' object.
// This method first looks in the Documents directory for
// the appropriate JavaScript file before falling back to any
// built-in JavaScript files.
- (BOOL)loadScriptNamed:(NSString*)fileName error:(NSError**)error  {
    
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
        return NO;
    }
    
    // Load the script and evaluate it.
    NSString* scriptText = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:error];
    
    if (scriptText == nil)
        return NO;
    
    JSStringRef scriptNameJSString = JSStringCreateWithNSString(fileName);
    
    // Create an object to use that any variables will go into
    JSObjectRef object = JSObjectMake(_scriptContext, NULL, NULL);
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    JSObjectSetProperty(_scriptContext, globalObject, scriptNameJSString, object, 0, NULL);
    
    JSStringRelease(scriptNameJSString);
    
    [self evaluateScript:scriptText error:error thisObject:object];
    
    return YES;
}

// Tidy up the script execution context.
- (void)dealloc {
    JSGlobalContextRelease(_scriptContext);
}

@end
