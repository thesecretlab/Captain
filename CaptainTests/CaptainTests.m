//
//  CaptainTests.m
//  JSDelegationTests
//
//  Created by Jon Manning on 9/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import "CaptainTests.h"
#import "Captain.h"

@interface TestObject : NSObject <JSCallableObject>

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

- (NSDictionary *)handlersForScriptMethods {
    return @{@"hello" : ^(NSArray* parameters) {
        return @"yes";
    }};
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
    
    // Functions in JS can be called into, and be provided with a 'this' object to access.
    code = @"function foo(a) { return this.name + a + \"test\" }";
    error = nil;
    testObject.name = @"Hello";
    
    [_context evaluateScript:code error:nil];
    
    returnValue = [_context callFunction:@"foo" withParameters:@[@" "] thisObject:testObject error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    STAssertEqualObjects(returnValue, @"Hello test", @"The function call should execute, receive parameters, and access the 'this' object.");
    
    // Objects can vend a handler block
    code = @"testObject.hello()";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown.", error);
    STAssertEqualObjects(returnValue, @"yes", @"The function call should return the correct value.");
    
}

- (void) testSingleFunctionRegistration {
    
    NSString* code;
    NSError* error;
    
    id returnValue;
    
    // Functions can be added
    JSFunction doSomethingFunction = ^(NSArray* parameters) {
        return @(1337);
    };
    
    [_context addFunction:doSomethingFunction withName:@"doSomething"];
    
    code = @"doSomething(1,2)";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be thrown");
    STAssertEqualObjects(@(1337), returnValue, @"The number 1337 should be returned");
    
    // Functions that handle parameters can be added
    JSFunction addOneThousandFunction = ^(NSArray* parameters) {
        NSNumber *number = parameters[0];
        return @(number.integerValue + 1000);
    };
    
    [_context addFunction:addOneThousandFunction withName:@"addOneThousand"];
    
    code = @"addOneThousand(doSomething())";
    error = nil;
    
    returnValue = [_context evaluateScript:code error:&error];
    
    STAssertNil(error, @"An error should not be returned");
    STAssertEqualObjects(@(2337), returnValue, @"The number 2337 should be returned");
    
    // Functions can be returned from JavaScript, and called from native code
    code = @"(function(a) {return a+1});";
    error = nil;
    returnValue = [_context evaluateScript:code error:nil];
    
    JSFunction returnedFunction = returnValue;
    STAssertNotNil(returnedFunction, @"The returned value should not be nil");
    
    NSNumber* returnedNumber = returnedFunction(@[@(1)]);
    
    STAssertEqualObjects(returnedNumber, @(2), @"The JS function, when called from native code, should return 2");

    
}

- (void) testFunctionCollectionRegistration {
    
    NSString* code;
    NSError* error;
    
    // Test adding a collection of functions
    JSFunction doSomethingFunction = ^(NSArray* parameters) {
        return @(1337);
    };
    JSFunction doSomethingElseFunction = ^(NSArray* parameters) {
        return @"Hello";
    };
    
    NSDictionary* functions = @{
        @"doSomething":doSomethingFunction,
        @"doSomethingElse":doSomethingElseFunction
    };
    
    [_context addFunctionsWithDictionary:functions withName:@"Test"];
    
    code = @"Test.doSomething() + Test.doSomethingElse()";
    error = nil;
    
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

- (void) testLoadingAllScripts {
    NSError* error = nil;
    BOOL succeeded = NO;
    
    succeeded = [_context loadAllAvailableScripts:&error];
    
    STAssertTrue(succeeded, @"Loading all scripts should succeed");
    STAssertNil(error, @"No error should be returned");
    
    NSNumber* result = [_context evaluateScript:@"TestExtensionScript.doSomething()" error:nil];
    
    STAssertEqualObjects(result, @123, @"The function should exist and return correctly");
    
}

- (void) testInheritance {
    
    NSError* error = nil;
    id returnValue = nil;
    
    returnValue = [_context evaluateFileNamed:@"InheritanceTests" error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    
    TestObject* testObject = [[TestObject alloc] init];
    
    testObject.name = @"Bob";
    
    returnValue = nil;
    error = nil;
    
    returnValue = [_context callFunction:@"doSomething" inSuite:@"SubModule" thisObject:testObject error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(returnValue, @"FooBar, Bob", nil);
    
    returnValue = nil;
    error = nil;
    
    returnValue = [_context callFunction:@"doSomethingImpressive" inSuite:@"SubModule" thisObject:testObject error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(returnValue, @"Yes", @"The prototype chain should be invoked.");
}

- (void) testCallingOtherObjects {
    
    NSError* error = nil;
    id returnValue = nil;
    
    returnValue  = [_context evaluateFileNamed:@"InheritanceTests" error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown");
    
    TestObject* object = [[TestObject alloc] init];
    
    [object useScriptObjectNamed:@"OtherModule" inScriptContext:_context];
    
    NSString* testParameter = @"Hello";
    
    returnValue = [object callScriptFunction:@"testFunction" parameters:@[testParameter] error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown");
    STAssertEqualObjects(returnValue, testParameter, @"The function should be called and return its parameter");
    
    TestObject* anotherObject = [[TestObject alloc] init];
    anotherObject.name = @"Foo";
    [anotherObject useScriptObjectNamed:@"SubModule" inScriptContext:_context];
    
    returnValue  = [object callScriptFunction:@"testCallingOtherFunction" parameters:@[anotherObject] error:&error];
    
    STAssertNil(error, @"An error %@ should not be thrown", error);
    STAssertEqualObjects(returnValue, @"FooBar, Foo", @"The function should be called");
    
}

- (void) testPoints {
    
    CGPoint point = CGPointMake(10, 10);
    
    NSError* error = nil;
    id returnValue = nil;
    
    [_context setProperty:@"point" toObject:JSPoint(point)];
    
    [_context evaluateScript:@"log(point.x)" error:&error];
    returnValue = [_context evaluateScript:@"point.x == 10 && point.y == 10" error:&error];
    
    STAssertEqualObjects(returnValue, @YES, @"Point should be accessed from JS");
    
    returnValue = nil;
    error = nil;
    
    returnValue = [_context evaluateScript:@"point = new Point(15,15)" error:&error];
    
    STAssertTrue([returnValue isKindOfClass:[NSValue class]], @"An NSValue should be returned");
    STAssertTrue(strcmp([returnValue objCType], @encode(CGPoint)) == 0, @"The returned value should be a point");
    
}


@end
