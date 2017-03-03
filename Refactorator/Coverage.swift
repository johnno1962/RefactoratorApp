//
//  Coverage.swift
//  Refactorator
//
//  Created by John Holdsworth on 03/03/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation

class Coverage {

    let covered: Set<Int>

    init?( file: String, project: Project ) {
        let coverageFile = project.derivedData.url
            .appendingPathComponent("Build/Intermediates/CodeCoverage/Coverage.profdata").path
        if !FileManager.default.fileExists(atPath: coverageFile) {
            return nil
        }

        let task = Process()
        task.launchPath = Bundle.main.path(forResource: "coverage", ofType: ".rb")
        task.arguments = [coverageFile, file]

        let output = Pipe()
        task.standardOutput = output.fileHandleForWriting
        task.launch()
        output.fileHandleForWriting.closeFile()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if let coverage = String(data: data, encoding: .utf8) {
            covered = Set<Int>( coverage.components(separatedBy: "\n").map { Int($0, radix:10) ?? -1 } )
        }
        else {
            return nil
        }
    }

}
