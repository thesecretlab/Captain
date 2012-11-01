//
//  JSContext.h
//  Captain
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "JSDefines.h"
#import "JSTypeConversion.h"
#import "JSObjectBridging.h"

@interface JSContext : NSObject

// Attempts to load a JavaScript file, first looking in the Documents folder (on iPhone), and then in the built-in bundle resources. Returns YES if the script was successfully loaded, NO otherwise. If there was an error loading the script and 'error' is non-nil, an NSError object will be placed inside 'error'.
- (BOOL)loadScriptNamed:(NSString*)fileName error:(NSError**)error;

// Executes the provided script, and returns the resulting value.
- (id) evaluateScript:(NSString*)script error:(NSError**)error;

// Reads and executes the named file, using the global object as 'this', and looking first in the Documents directory, followed by the bundle resources.
- (id) evaluateFile:(NSString*)fileName error:(NSError**)error;

// Registers a single function block in the JavaScript context, associating it with the given name. The function will be added to the Javascript context's global namespace.
- (void) addFunction:(JSFunction)function withName:(NSString*)functionName;

- (void) addFunctionsWithDictionary:(NSDictionary*)functionDictionary withName:(NSString*)functionDictionaryName;

- (void) setProperty:(NSString*)propertyName toObject:(id)object;


- (id) callFunction:(NSString*)functionName inSuite:(NSString*)suiteName thisObject:(NSObject*)thisObject error:(NSError**) error;

- (id) callFunction:(NSString*)functionName inSuite:(NSString*)suiteName parameters:(NSArray*)parameters thisObject:(NSObject*)thisObject error:(NSError**) error;

- (id) callFunction:(NSString*)functionName withParameters:(NSArray*)parameters thisObject:(NSObject*)thisObject error:(NSError**)error;

// Loads all scripts, first checking in Documents and then in the bundle. If a file exists in Documents and an identically-named file exists in the bundle, the bundle version is not loaded.
// Returns YES if no errors, NO otherwise.
- (BOOL) loadAllAvailableScripts:(NSError**)error;

@end
