//
//  JSContext.m
//  Captain
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JSContext.h"
#import <objc/objc-runtime.h>

static char* JSObjectDeallocBlockKey = "JSObjectDeallocBlockKey";
static char* JSObjectScriptContextKey = "JSObjectScriptContextKey";
static char* JSObjectScriptObjectKey = "JSObjectScriptObjectKey";

typedef void(^RunOnDeallocBlock)(void);

@interface JSDeallocBlock : NSObject

@property (copy) RunOnDeallocBlock deallocBlock;

@end

@implementation JSDeallocBlock

- (void)dealloc {
    if (self.deallocBlock)
        self.deallocBlock();
}

@end

@interface JSContext ()

- (JSObjectRef) _objectRefForProperty:(NSString*)propertyName inObject:(JSObjectRef)object;
- (JSObjectRef) _globalObject;

- (JSContextRef) _scriptContext;

@end




@implementation NSObject (JSObjectAssociation)

- (void)useScriptObjectNamed:(NSString *)scriptObject inScriptContext:(JSContext *)context {
    self.scriptContext = context;
    self.scriptObject = [context _objectRefForProperty:scriptObject inObject:[context _globalObject]];    
}

- (id)callScriptFunction:(NSString *)functionName error:(NSError *__autoreleasing *)error {
    return [self callScriptFunction:functionName parameters:nil error:error];    
}

- (id)callScriptFunction:(NSString *)functionName parameters:(NSArray *)parameters error:(NSError *__autoreleasing *)error {
    
    JSObjectRef functionObject = [self.scriptContext _objectRefForProperty:functionName inObject:self.scriptObject];
    
    if (functionObject == nil)
        return nil;
    
    JSValueRef exception = nil;
    
    id returnValue = CallFunctionObject(self.scriptContext._scriptContext, functionObject, parameters, self, self.scriptObject, &exception);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(self.scriptContext._scriptContext, exception);
        NSLog(@"%@", errorString);
        if (error != nil) {
            
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
        return nil;
    }
    
    return returnValue;
    
}


- (void)setScriptContext:(JSContext *)scriptContext {
    objc_setAssociatedObject(self, JSObjectScriptContextKey, scriptContext, OBJC_ASSOCIATION_RETAIN);
}

- (JSContext *)scriptContext {
    return objc_getAssociatedObject(self, JSObjectScriptContextKey);
}

- (void)setScriptObject:(JSObjectRef)scriptObject {
    if (objc_getAssociatedObject(self, JSObjectDeallocBlockKey) == nil) {
        
        // TODO: Possibly a retain cycle here - dealloc is never being called on the JSDeallocBlock
        JSDeallocBlock* deallocBlock = [[JSDeallocBlock alloc] init];
        
        __weak NSObject* weakSelf = self;
        deallocBlock.deallocBlock = ^{
            weakSelf.scriptObject = nil;
        };
        objc_setAssociatedObject(self, JSObjectDeallocBlockKey, deallocBlock, OBJC_ASSOCIATION_RETAIN);
    }
    
    JSObjectRef formerObject = self.scriptObject;
    
    if (formerObject)
        JSValueUnprotect(self.scriptContext._scriptContext, formerObject);
    
    JSValueProtect(self.scriptContext._scriptContext, scriptObject);
    
    objc_setAssociatedObject(self, JSObjectScriptObjectKey, [NSValue valueWithPointer:scriptObject], OBJC_ASSOCIATION_RETAIN);
}

- (JSObjectRef)scriptObject {
    NSValue* value = objc_getAssociatedObject(self, JSObjectScriptObjectKey);
    
    return value.pointerValue;
}

@end

@implementation JSContext {
    JSGlobalContextRef _scriptContext;
    NSMutableArray* _loadedScriptNames;
}

- (id)init
{
    self = [super init];
    if (self) {
        _scriptContext = JSGlobalContextCreate(NULL);
        
        _loadedScriptNames = [NSMutableArray array];
        
        // Register a simple 'log' method that scripts can use
        [self addFunction:^id(NSArray *parameters) {
            NSLog(@"%@", [parameters componentsJoinedByString:@" "]);
            
            return nil;
        } withName:@"log"];
        
        __weak id weakSelf = self;
        [self addFunction:^id(NSArray *parameters) {
            [weakSelf loadScriptNamed:parameters[0] error:nil];
            return nil;
        } withName:@"require"];
        
        // Prepare prototype objects
        JSStringRef name = JSStringCreateWithUTF8CString("Point");
        JSObjectRef pointPrototype = JSObjectMake(_scriptContext, PointValueClass(), NULL);
        JSObjectSetProperty(_scriptContext, JSContextGetGlobalObject(_scriptContext), name, pointPrototype, kJSPropertyAttributeReadOnly, NULL);
        JSStringRelease(name);
        
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
            
            NSDictionary* errorObject = (id)NSObjectWithJSValue(_scriptContext, exception);
            
            NSString* errorString;
            
            if ([errorObject isKindOfClass:[NSDictionary class]]) {
                errorString = NSStringWithJSValue(_scriptContext, exception);
                
                errorString = [NSString stringWithFormat:@"Line %@: %@", [errorObject objectForKey:@"line"], errorString];
            } else if ([errorObject isKindOfClass:[NSString class]]) {
                errorString = (id)errorObject;
            } else {
                errorString = @"Unknown error";
            }
            
            
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
    return [self _callFunction:functionName withParameters:parameters thisObject:thisObject prototype:NULL error:error];
}


- (id) _callFunction:(NSString*)functionName withParameters:(NSArray*)parameters thisObject:(NSObject*)thisObject prototype:(JSObjectRef)prototype error:(NSError**)error {
    
    if (functionName == nil)
        return nil;
    
    JSValueRef exception = nil;
    
    // Evaluate which object this function name is referring to
    JSStringRef functionNameJSString = JSStringCreateWithNSString(functionName);
    JSValueRef evaluatedValue = JSEvaluateScript(_scriptContext, functionNameJSString, NULL, NULL, 0, &exception);
    
    JSStringRelease(functionNameJSString);
    
    // Could we find it?
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        NSLog(@"%@", errorString);
        if (error != nil) {
            
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
        return nil;
    }
    
    
    // We have the value that it evaluated to; now we need to
    // if figure out if it's a callable object.
    
    
    // Is it an object?
    JSObjectRef object = JSValueToObject(_scriptContext, evaluatedValue, &exception);
    
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        NSLog(@"%@", errorString);
        if (error != nil) {
            
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
        return nil;
    }
    
    // Is it a _callable_ object?
    if (JSObjectIsFunction(_scriptContext, object) == NO && error != nil) {
        NSString* errorString = [NSString stringWithFormat:@"%@ is not callable", functionName];
        NSLog(@"%@", errorString);
        if (error != nil) {
            
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
        return nil;
    }
    
    // Ok, call it!
    id returnValue = CallFunctionObject(_scriptContext, object, parameters, thisObject, prototype, &exception);
    
    // Was there an exception?
    if (exception != nil) {
        NSString* errorString = NSStringWithJSValue(_scriptContext, exception);
        NSLog(@"%@", errorString);
        if (error != nil) {
            
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:errorString}];
        }
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
    
    if ([_loadedScriptNames containsObject:[fileName stringByDeletingPathExtension]])
        return NO;
    
    JSStringRef scriptName = JSStringCreateWithNSString([fileName stringByDeletingPathExtension]);
    JSObjectRef globalObject = JSContextGetGlobalObject(_scriptContext);
    JSObjectRef containerObject = JSObjectMake(_scriptContext, NULL, NULL);
    JSObjectSetProperty(_scriptContext, globalObject, scriptName, containerObject, 0, NULL);
    
    [_loadedScriptNames addObject:[fileName stringByDeletingPathExtension]];
    
    return [self evaluateFileAtURL:[self urlForScriptNamed:fileName] error:error] != nil;
    
}

- (NSURL*)urlForScriptNamed:(NSString*)fileName {
    
    if ([[fileName pathExtension] isEqualToString:@"js"] == NO) {
        fileName = [fileName stringByAppendingPathExtension:@"js"];
    }
    
#if TARGET_OS_IPHONE
    // If we're running on the iPhone, look for the file in the
    // Documents folder first.
    
    NSURL* documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    
    
    NSEnumerator* documentResourcesEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:documentsURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    
    for (NSURL* resourceURL in documentResourcesEnumerator) {
        if ([[[resourceURL lastPathComponent] stringByDeletingPathExtension] isEqualToString:fileName]) {
            return resourceURL;
        }
    }
    
#endif
    
    NSURL* bundleResourceURL = [[NSBundle bundleForClass:[self class]] resourceURL];
    NSEnumerator* resourcesEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:bundleResourceURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    
    for (NSURL* resourceURL in resourcesEnumerator) {
        if ([[resourceURL lastPathComponent] isEqualToString:fileName]) {
            return resourceURL;
        }
    }
    
    return nil;
}

- (id) evaluateFileAtURL:(NSURL*)scriptURL error:(NSError**)error {
    
    // Load the script and evaluate it.
    NSString* scriptText = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:error];
    
    if (scriptText == nil)
        return NO;
    
    id returnValue = [self evaluateScript:scriptText error:error];
    
    if (error && *error != nil) {
        // prepend the file name to the error's description key
        NSString* description = [*error localizedDescription];
        description = [NSString stringWithFormat:@"%@, %@", [scriptURL lastPathComponent], description];
        
        *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:description}];
    }
    
    return returnValue;
    
}

- (id)evaluateFileNamed:(NSString *)scriptFileName error:(NSError **)error {
    if ([[scriptFileName pathExtension] isEqualToString:@"js"])
        scriptFileName = [scriptFileName stringByDeletingPathExtension];
    
    NSURL* url = [[NSBundle bundleForClass:[self class]] URLForResource:scriptFileName withExtension:@"js"];
    
    if (url == nil) {
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"JavaScript" code:0 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Can't find script %@", scriptFileName]}];
        }
        return nil;
    }
    
    return [self evaluateFileAtURL:url error:error];
}

- (id) callFunction:(NSString*)functionName withObject:(NSObject*)thisObject error:(NSError**)error {
    return [self callFunction:functionName inSuite:NSStringFromClass([thisObject class]) thisObject:thisObject error:error];
}

- (id) callFunction:(NSString *)functionName withObject:(NSObject *)thisObject  parameters:(NSArray *)parameters error:(NSError **)error {
    return [self callFunction:functionName inSuite:NSStringFromClass([thisObject class]) parameters:parameters thisObject:thisObject error:error];
}

- (id) callFunction:(NSString*)functionName inSuite:(NSString*)suiteName thisObject:(NSObject*)thisObject error:(NSError**) error {
    return [self callFunction:functionName inSuite:suiteName parameters:nil thisObject:thisObject error:error];
    
}

- (id) callFunction:(NSString*)functionName inSuite:(NSString*)suiteName parameters:(NSArray*)parameters thisObject:(NSObject*)thisObject error:(NSError**) error {
    functionName = [suiteName stringByAppendingFormat:@".%@", functionName];
    
    JSObjectRef suiteObject = [self _objectRefForProperty:suiteName inObject:NULL];
    
    return [self _callFunction:functionName withParameters:parameters thisObject:thisObject prototype:suiteObject error:error];
}

- (JSObjectRef) _objectRefForProperty:(NSString*)propertyName inObject:(JSObjectRef)object {
    
    if (propertyName == nil)
        return NULL;
    
    JSStringRef propertyNameJS = JSStringCreateWithNSString(propertyName);
    
    if (object == nil)
        object = JSContextGetGlobalObject(_scriptContext);
    
    JSValueRef exception = nil;
    
    JSValueRef value = JSObjectGetProperty(_scriptContext, object, propertyNameJS, &exception);
    
    JSStringRelease(propertyNameJS);
    
    if (exception != nil)
        return nil;
    
    return JSValueToObject(_scriptContext, value, NULL);
    
}

- (BOOL)loadAllAvailableScripts:(NSError *__autoreleasing *)error {
    
    NSMutableArray* loadedScripts = [NSMutableArray array];
    
#if TARGET_OS_IPHONE
    // If we're running on the iPhone, look for the file in the
    // Documents folder first.
    
    NSURL* documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    
    
    NSEnumerator* documentResourcesEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:documentsURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    
    for (NSURL* resourceURL in documentResourcesEnumerator) {
        if ([[resourceURL pathExtension]isEqualToString:@"js"]) {
            NSString* fileName = [[resourceURL lastPathComponent] stringByDeletingPathExtension];
            [self loadScriptNamed:fileName error:error];
            
            if (error != nil && *error != nil)
                return NO;
            
            [loadedScripts addObject:fileName];
        }
    }
    
#endif
    
    NSURL* bundleResourceURL = [[NSBundle bundleForClass:[self class]] resourceURL];
    NSEnumerator* resourcesEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:bundleResourceURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    
    for (NSURL* resourceURL in resourcesEnumerator) {
        if ([[resourceURL pathExtension]isEqualToString:@"js"]) {
            NSString* fileName = [[resourceURL lastPathComponent] stringByDeletingPathExtension];
            [self loadScriptNamed:fileName error:error];
            
            if (error != nil && *error != nil)
                return NO;
            
            [loadedScripts addObject:fileName];
        }
    }
    
    // All loaded scripts get their "load" function called
    
    for (NSString* scriptName in loadedScripts) {
        NSLog(@"Loaded script %@", scriptName);
        
        JSObjectRef object = [self _objectRefForProperty:scriptName inObject:nil];
        JSObjectRef loadFunction = [self _objectRefForProperty:@"load" inObject:object];
        
        if (loadFunction == NULL)
            continue;
        
        JSValueRef exception = nil;
        
        JSObjectCallAsFunction(_scriptContext, loadFunction, NULL, 0, NULL, &exception);
        
        if (exception != nil) {
            NSLog(@"Error calling load() for %@: %@", scriptName, NSStringWithJSValue(_scriptContext, exception));
        }
        
    }
    
    
    return YES;
    
    
}

- (JSObjectRef)_globalObject {
    return JSContextGetGlobalObject(_scriptContext);
}

- (JSContextRef)_scriptContext {
    return _scriptContext;
}

// Tidy up the script execution context.
- (void)dealloc {
    JSGlobalContextRelease(_scriptContext);
}

@end
