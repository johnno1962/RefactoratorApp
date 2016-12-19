//
//  Common.swift
//  Refactorator
//
//  Created by John Holdsworth on 18/12/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Foundation

var xcode: AppLogging!

protocol AppLogging {
    func log( _ msg: String )
    func error( _ msg: String )
}

func htmlEscape( _ str: String? ) -> String {
    if let str = str {
        return str.contains("<") || str.contains("&") ?
            str.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;") : str
    }
    return "nil"
}

extension Process {

    @discardableResult
    class func run(path: String, args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

}

extension DispatchGroup {

    class func inParallel<T>( work: [T], workers: Int = 4,
                          processor: @escaping (T, @escaping (() -> Void) -> Void) -> Void ) {
        let threadPool = DispatchGroup()
        let lock = NSLock()
        func locked<L>( block: () -> L ) -> L {
            lock.lock()
            let ret = block()
            lock.unlock()
            return ret
        }

        var work = work
        for _ in 0..<workers {
            threadPool.enter()
            DispatchQueue.global().async {
                while let next = locked( block: {
                    () -> T? in
                    return !work.isEmpty ? work.removeFirst() : nil
                } ) {
                    processor( next, locked )
                }

                threadPool.leave()
            }
        }

        threadPool.wait()
    }

}
