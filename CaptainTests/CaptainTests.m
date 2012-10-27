//
//  JSDelegationTests.m
//  JSDelegationTests
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "JSDelegationTests.h"
#import "JSContext.h"

@interface TestObject : NSObject

@property (strong) NSString* name;
@property (strong) TestObject* childObject;

@end

@implementation TestObject

- (NSString*)handleTest:(NSArray*)parameters {
    return @"Hello";
}

- (NSNumber*)handleTestWithParameters:(NSArray*)parameters {
    
    
    
    return @(1337 + [parameters[0] integerValue]);
}

@end

@implementation JSDelegationTests {
    JSContext* _context;
}

- (void)setUp
{
    [super setUp];
    
    _context = [[JSContext alloc] init];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    _context = nil;
    
    [super tearDown];
}

- (void) testLoadingScripts {
    NSString* code;
    NSError* error;
    
    id returnValue;
    
    [_context loadScriptNamed:@"TestExtensionScript" error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    
    code = @"TestExtensionScript.doSomething()";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    
}

- (void) testObjectInteraction {
    
    NSString* code;
    NSError* error;
    
    id returnValue;
    
    // Objects can be placed into the JS context, and their
    // properties can be accessed.
    TestObject* testObject = [[TestObject alloc] init];
    testObject.name = @"Hello";
    
    testObject.childObject = [[TestObject alloc] init];
    testObject.childObject.name = @"World";
    
    [_context setProperty:@"testObject" toObject:testObject];
    
    code = @"testObject.name";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(returnValue, testObject.name, @"The property on the object should be accessible.");
    
    code = @"testObject.name = \"internet\"";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(testObject.name, @"internet", @"The property should be settable.");
    
    code = @"testObject.doesNotExist = \"123\"";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNotNil(error, @"An error should be thrown.");
    
    // NSObjects referenced by other NSObjects should be accessible.
    code = @"testObject.childObject.name = \"Captain Planet\"";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(testObject.childObject.name, @"Captain Planet", @"A property of a native object referenced via another native object should be accessible.");
    
    // If an object has a method "handleTest:", that method can be
    // called as the function "test".
    code = @"testObject.test()";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    STAssertEqualObjects(returnValue, @"Hello", @"The method should be called and return the string 'Hello'.");
    
    code = @"testObject.testWithParameters(1000)";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    STAssertEqualObjects(returnValue, @(2337), @"The method should be called and handle parameters.");
    
    // Functions in JS can be called into.
    code = @"function foo(a) { return this.name + a + \"test\" }";
    error = nil;
    testObject.name = @"Hello";
    
    [_context evaluateScript:code error:nil];
    
    returnValue = [_context callFunction:@"foo" withParameters:@[@" "] object:testObject error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    STAssertEqualObjects(returnValue, @"Hello test", @"The function call should execute, receive parameters, and access the 'this' object.");
    
}

- (void) testSingleFunctionRegistration {
    
    NSString* code;
    NSError* error;
    
    id returnValue;
    
    // Simple function test
    JSExtensionFunction doSomethingFunction = ^(NSArray* parameters) {
        return @(1337);
    };
    
    [_context addFunction:doSomethingFunction withName:@"doSomething"];
    
    code = @"doSomething(1,2)";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be thrown");
    STAssertEqualObjects(@(1337), returnValue, @"The number 1337 should be returned");
    
    // Parameter handling test
    
    JSExtensionFunction addOneThousandFunction = ^(NSArray* parameters) {
        NSNumber *number = parameters[0];
        return @(number.integerValue + 1000);
    };
    
    [_context addFunction:addOneThousandFunction withName:@"addOneThousand"];
    
    code = @"addOneThousand(doSomething())";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be returned");
    STAssertEqualObjects(@(2337), returnValue, @"The number 2337 should be returned");
    
}

- (void) testFunctionCollectionRegistration {
    
    // Test adding a collection of functions
    JSExtensionFunction doSomethingFunction = ^(NSArray* parameters) {
        return @(1337);
    };
    JSExtensionFunction doSomethingElseFunction = ^(NSArray* parameters) {
        return @"Hello";
    };
    
    NSDictionary* functions = @{
        @"doSomething":doSomethingFunction,
        @"doSomethingElse":doSomethingElseFunction
    };
    
    [_context addFunctionsWithDictionary:functions withName:@"Test"];
    
    NSString* code = @"Test.doSomething() + Test.doSomethingElse()";
    NSError* error = nil;
    
    id returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be thrown");
    STAssertEqualObjects(@"1337Hello", returnValue, @"The string 1337Hello should be returned");
    
}

- (void)testScriptEvaluation
{
    NSString* code;
    NSError* error;
    
    id returnValue;
    
    // Test simple scripts
    code = @"1+1";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"No error should be generated");
    STAssertEqualObjects(@(2), returnValue, @"Code should return @(2)");
    
    // Test errors
    code = @"doesNotExist";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNotNil(error, @"An error should be thrown");
    
    code = @"dict = {foo:1, bar:2}; dict.bas = 3; dict";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be thrown");
    STAssertTrue([returnValue isKindOfClass:[NSDictionary class]], @"Value returned should be a dictionary");
    
    NSDictionary* returnedDictionary = returnValue;
    
    STAssertEqualObjects(returnedDictionary[@"foo"], @(1), @"The dictionary should contain a number value of 1 for key 'foo'");
    
}


@end
