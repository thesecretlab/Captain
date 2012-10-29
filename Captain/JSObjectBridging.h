//
//  Header.h
//  Captain
//
//  Created by Jon Manning on 27/10/12.
//  Copyright (c) 2012 Secret Lab. All rights reserved.
//

#import <JavaScriptCore/JavaScriptCore.h>

// Returns the shared class definition for block function wrappers.
JSClassRef BlockFunctionClass();

// Returns the shared class definition for native object wrappers.
JSClassRef NativeObjectClass();