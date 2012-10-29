//
//  JSDefines.h
//  Captain
//
//  Created by Jon Manning on 27/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

typedef id(^JSFunction)(NSArray* parameters);

@protocol JSCallableObject <NSObject>

- (NSDictionary*) handlersForScriptMethods;

@end

