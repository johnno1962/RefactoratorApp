//
//  Utils.h
//  Refactorator
//
//  Created by John Holdsworth on 19/11/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern int _system( const char *cmd );

@interface Utils : NSObject
+ (NSString *)hashStringForPath:(NSString *)path;
@end
