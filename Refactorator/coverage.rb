#!/usr/bin/ruby

#  coverage.rb
#  Refactorator
#
#  Created by John Holdsworth on 03/03/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

profdata, source = ARGV

objectdir = File.dirname( profdata )
classname = File.basename( source, ".swift" )

Dir.chdir(objectdir)

object = Dir.glob("**/#{classname}.o").first

coverage = `xcrun llvm-cov show -instr-profile '#{profdata}' '#{object}'`

coverage.scan( /^\s+(\d+)\|\s+(\d+)\|/ ) do |covered, line|
    if covered != "0"
        puts( "#{line}\n" )
    end
end
