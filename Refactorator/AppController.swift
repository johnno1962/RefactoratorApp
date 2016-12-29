//
//  AppState.swift
//  Refactorator
//
//  Created by John Holdsworth on 13/12/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Foundation
import WebKit

class AppController: NSObject, AppGui, WebUIDelegate, WebFrameLoadDelegate, WebPolicyDelegate {

    @IBOutlet weak var window: NSWindow!

    @IBOutlet weak var sourceView: WebView!
    @IBOutlet weak var changesView: WebView!
    weak var printWebView: WebView!

    let canvizEntity = Entity(file: "[Dependencies]")
    var canvizView: WebView!

    @IBOutlet weak var replacement: NSTextField!
    @IBOutlet weak var findText: NSTextField!

    @IBOutlet var backItem: NSMenuItem!
    @IBOutlet var forwardItem: NSMenuItem!
    @IBOutlet var reloadItem: NSMenuItem!
    @IBOutlet var dependsItem: NSMenuItem!
    @IBOutlet var searchItem: NSMenuItem!

    var history = [Entity]()
    var future = [Entity]()
    var project: Project?

    var html = "", oldValue = "", changes = ""
    var wasSearch = false

    var entitiesByFile = [[Entity]]()
    var originals = [String:NSData]()
    var modified = [String:NSData]()
    var linecounts = [String:Int]()

    var formatter = Formatter()

    func log( _ msg: String ) {
        appendSource(title: "", text: "<div class=log>\(msg)</div>")
        Swift.print( msg )
    }

    func error( _ msg: String ) {
        window.title = msg
        log( "<div class=error>\(msg)</div>" )
    }

    func open( url: String ) {
        NSWorkspace.shared().open(url.url)
    }
    
    func sourceHTML() -> String {
        let path = Bundle.main.path(forResource: "Source", ofType: "html")!
        return try! String(contentsOfFile: path, encoding:.utf8)
    }

    func defaultEntity() -> Entity {
        if let recentSource = NSDocumentController.shared().recentDocumentURLs.first {
            let entity = Entity(file: recentSource.path)
            project = Project(target: entity)
            return entity
        }
        return Entity(file: Bundle.main.path(forResource: "Intro", ofType: "html")!)
    }

    @discardableResult
    func setupChanges() -> String {
        let code = sourceHTML()
        if changesView.uiDelegate == nil {
            changesView.uiDelegate = self
            changesView.frameLoadDelegate = self
            changesView.mainFrame.loadHTMLString(code+"<div>Click on a symbol to locate references to rename</div>", baseURL: nil)
            changesView.windowScriptObject.setValue(self, forKey:"appController2")
            changesView.policyDelegate = self
        }
        return code
    }

    func setup( target: Entity? = nil, cascade: Bool = true ) {
        let code = setupChanges()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if target != canvizEntity {
            project = Project(target: target)
            canvizView?.removeFromSuperview()
        }
        else {
            if canvizView == nil {
                canvizView = WebView(frame: sourceView.frame)
                canvizView.autoresizingMask = sourceView.autoresizingMask
                canvizView.frameLoadDelegate = self
                canvizView.uiDelegate = self
                let path = Bundle.main.path(forResource: "canviz", ofType: "html")!
                canvizView.mainFrame.load( URLRequest( url: path.url ) )
            }
            else {
                canvizView.frame = sourceView.frame
            }
            sourceView.superview?.addSubview(canvizView)
            history.append( canvizEntity )
            return
        }

        let target = target ?? project?.entity ?? defaultEntity()

        if printWebView == nil {
            printWebView = sourceView
        }
        setLocation(entity: target)
        future.removeAll()

        if let sourceData = NSData(contentsOfFile: target.file) {
            if target.sourceName == "Intro.html" {
                html = String(data:sourceData as Data, encoding:.utf8)!
            }
            else {
                let entities = project?.indexDB?.entitiesFor(filePath: target.file)
                html = formatter.htmlFor(path: target.file, data: sourceData, entities: entities,
                               selecting: target, cascade: cascade, cleanPath: relative(target.file)).joined()
            }

            if sourceView.uiDelegate == nil {
                sourceView.uiDelegate = self
                sourceView.frameLoadDelegate = self
                sourceView.mainFrame.loadHTMLString(code, baseURL: nil)
            }
            else {
                sourceView.windowScriptObject.callWebScriptMethod("setSource", withArguments: [html])
            }
        }
        else {
            xcode.error("Could not open \(target.file)")
        }
    }

    func setLocation( entity: Entity ) {
        if entity != history.last || entity.offset != history.last?.offset {
            history.append( entity )
        }
        if entity.sourceName == "Intro.html" {
            return
        }

        let sourceURL = entity.file.url
        NSDocumentController.shared().noteNewRecentDocumentURL(sourceURL)
        let sourceDir = sourceURL.deletingLastPathComponent().path
        if var workspace = project?.workspaceName {
            if !IndexDB.projectIncludes(file: entity.file) {
                workspace = "Incorrect frontmost open workspace \(workspace)"
            }
            window.title = "\(sourceURL.lastPathComponent) – \(sourceDir.replacingOccurrences(of: HOME, with: "~")) – \(workspace)"
        }
    }
    
    @objc func webView( _ webView: WebView, addMessageToConsole message: NSDictionary ) {
        Swift.print("\(message)")
    }

    @objc func webView(_ sender: WebView!, runJavaScriptAlertPanelWithMessage message: String!, initiatedBy frame: WebFrame!) {
        print("\(message)")
    }

    @objc func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        guard let win = sender.windowScriptObject else { return }
        if sender == sourceView {
            sourceView.policyDelegate = self
            win.setValue(self, forKey:"appController")
            win.callWebScriptMethod("setSource", withArguments: [html])
        }
        else if sender == changesView {
            win.setValue(self, forKey:"appController2")
        }
        else if sender == canvizView {
            win.setValue(self, forKey:"appController")
        }
    }

    @objc func webView(_ webView: WebView!, decidePolicyForNavigationAction actionInformation: [AnyHashable : Any]!,
                       request: URLRequest!, frame: WebFrame!, decisionListener listener: WebPolicyDecisionListener!) {
        if request.url!.scheme != "about" {
            NSWorkspace.shared().open(request.url!)
            listener.ignore()
        }
        else {
            listener.use()
        }
    }

    @objc func webView(_ sender: WebView!, contextMenuItemsForElement element: [AnyHashable : Any]!, defaultMenuItems: [Any]!) -> [Any]! {
        return [backItem, forwardItem, reloadItem, dependsItem, searchItem]
    }
    
    func setChangesSource( header: String? = nil, target: Entity? = nil, isApply: Bool = false ) {
        window.makeKeyAndOrderFront(nil)
        if changesView.uiDelegate == nil {
            setupChanges()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        if !isApply, let last = history.last, last != canvizEntity {
            project = Project(target: target ?? last)
        }

        let args = [header != nil ? "<div class=changesHeader>\(header!)</div>" : ""]
        changesView.windowScriptObject.setValue(self, forKey:"appController2")
        changesView.windowScriptObject.callWebScriptMethod("setSource", withArguments: args)
        if project?.indexDB == nil {
            xcode.error("No index DB found for project: \(project?.workspacePath ?? "unavailable")")
        }
    }

    func appendSource( title: String, text: String ) {
        changesView.windowScriptObject.callWebScriptMethod("appendSource", withArguments: [title, text])
    }

    func relative( _ path: String ) -> String {
        return project != nil ? path
            .replacingOccurrences(of: project!.projectRoot+"/", with: "")
            .replacingOccurrences(of: HOME+"/", with: "") : path
    }

    @objc override class func isSelectorExcluded( fromWebScript aSelector: Selector ) -> Bool {
        return aSelector != #selector(selected(text:title:line:col:offset:metaKey:)) &&
            aSelector != #selector(changeSelected(text:title:line:col:offset:metaKey:)) &&
            aSelector != #selector(depends(path:)) && aSelector != #selector(graphvizExport)
    }
    
    @objc public func selected( text: String, title: String, line: Int, col: Int, offset: Int, metaKey: Bool ) {
        let entity = Entity(file: history.last?.file ?? title.components(separatedBy: "#")[0],
                            line: line, col: col, offset: offset)

        setChangesSource(target: entity)
        replacement.stringValue = text
        printWebView = sourceView
        entitiesByFile.removeAll()
        oldValue = text

        if project?.indexDB == nil {
            xcode.error("Unable to open index db. Best guess at path was:\n\(project!.indexPath)")
            return
        }

        let sourcePath = entity.file
        if !IndexDB.projectIncludes(file: sourcePath) {
            xcode.error("File does not seem to be in the project. Is the wrong project open in the frontmost window of Xcode?\n\n")
        }

        if let indexDB = project?.indexDB {
            if let usrIDs = indexDB.usrIDsFor(filePath: sourcePath, line: line, col: col) {

                if metaKey, let entity = indexDB.declarationFor(filePath: sourcePath, line: line, col: col) {
                    setup(target: entity, cascade: false)
                    return
                }

                setLocation(entity: entity)

                let usrs = usrIDs.map { IndexDB.resolutions[$0] ?? "??\($0)" }
                let usrText = usrs.sorted { demangle( $0 )! < demangle( $1 )! }
                    .map { "USR: <span title=\"\($0)\">\(htmlEscape( demangle( $0 ) ))</span>\n" }.joined()
                appendSource(title: project!.indexPath, text: "<div class=usr>\(usrText)</div>" )

                var system = false
                var pathSeen = [String:Int]()
                _ = indexDB.entitiesFor(usrIDs: usrIDs) {
                    (entities) in

                    let path = entities[0].file
                    if let seen = pathSeen[path] {
                        xcode.log("Already seen \(path) \(seen) times")
                        pathSeen[path] = seen + 1
                    }
                    else {
                        pathSeen[path] = 1
                    }

                    if path.contains("/Developer/Platforms/") ||
                        path.contains("/Developer/Toolchains/" ) {
                        system = true
//                        return
                    }

                    entitiesByFile.append( entities )
                }

                processEntities(type: "references")
                if system {
                    appendSource(title: "", text: "\nToolchain symbol")
                }
            }
            else {
                xcode.log("<span title=\"\(project?.indexPath ?? "")\">No USR associated with \(entity.sourceName)#\(line):\(col) in project: \(project!.workspaceName). Is indexing complete?</span>")
                Process.run(path: "/usr/bin/touch", args: [entity.file])
            }
        }
        else {
            xcode.error("Could load load index db for project \(project?.workspacePath ?? "unknown")")
        }
    }

    @objc public func changeSelected( text: String, title: String, line: Int, col: Int, offset: Int, metaKey: Bool ) {
        let sourcePath = title.components(separatedBy: "#")[0]
        printWebView = changesView
        if  !metaKey {
            setup(target: Entity(file: sourcePath, line: line, col: col, offset: offset), cascade: false)
        }
        else if let indexDB = project?.indexDB,
            let entity = indexDB.declarationFor(filePath: sourcePath, line: line, col: col) {
            setup(target: entity, cascade: false)
        }
    }

    func filtered( _ lines: [String], _ entities: [Entity] ) -> String {
        var path = entities[0].file, filename = relative( path )
        filename = filename.substring(from: filename.range(of: "SDKs")?.lowerBound ?? filename.startIndex)
        let body = Set( entities.map { $0.line } ).sorted().map { lines[$0-1] }.joined()
        return "<a class=sourceLink href=\"file:\(path)\">\(filename)</a>\n<div class='changesEntry'>\(body)</div>"
    }

    func processEntities(type: String) {
        var changes = 0, files = 0

        for entities in entitiesByFile.sorted( by: { $0[0].file < $1[0].file } ) {
            let path = entities[0].file
            if let sourceData = NSData(contentsOfFile: path) {
                let lines = formatter.htmlFor(path: path, data: sourceData, entities: entities)
                appendSource(title: path, text: filtered(lines, entities))
                linecounts[path] = lines.count

                changes += entities.count
                files += 1
            }
            else {
                xcode.log("Could not read \(path)")
            }
        }

        appendSource(title: "", text: "\(changes) \(type) in \(files) file"+(files==1 ? "" : "s"))
    }

    @objc func depends( path: String ) {
        setChangesSource(header: "Dependencies on \(relative(path))")
        if let indexDB = project?.indexDB {
            entitiesByFile = indexDB.dependsOn(path: path)
        }
        processEntities(type: "dependencies")
    }

    @objc func graphvizExport() {
        open(url: formatter.gvfile)
    }

    func applySubstitution(oldValue: String, newValue: String) {
        let newData = newValue.data(using: .utf8)!
        let skew = newData.count - oldValue.utf8.count
        setChangesSource(header: "Applying replacement of '\(oldValue)' with '\(newValue)'", isApply: true)

        var modifications = 0
        for entities in entitiesByFile.sorted( by: { $0[0].file < $1[0].file } ) {
            let path = entities[0].file
            if let contents = modified[path] ?? NSData(contentsOfFile: path) {
                if originals[path] == nil {
                    originals[path] = contents
                }

                let out = NSMutableData()
                var pos = 0, mods = 0
                for entity in entities {
                    if let matches = entity.regex(text: oldValue).match(input: contents), Int(matches[2].rm_so) >= pos {
                        let startOffset = Int(matches[2].rm_so)
                        out.append( contents.subdata( with: NSMakeRange(pos, startOffset-pos) ) )

                        if let entity = history.last, path == entity.file && startOffset == entity.offset {
                            entity.offset = out.length
                        }
                        entity.offset = out.length

                        out.append( newData )
                        pos = Int(matches[2].rm_eo)
                        modifications += 1
                        mods += 1
                    }
                    else if wasSearch {
                        entity.notMatch = true
                    }
                    else {
                        xcode.log("Could not match \(newValue) at \(path)#\(entity.line):\(entity.col)")
                    }
                }

                out.append( contents.subdata( with: NSMakeRange(pos, contents.length-pos) ) )
                modified[path] = out

                let lines = formatter.htmlFor(path: path, data: out, entities: entities, skew: skew)
                appendSource(title: path, text: filtered(lines, entities))
                if lines.count != linecounts[path] {
                    xcode.log("Mismatched linecount \(lines.count) != \(linecounts[path]) for \(path)")
                }
            }
        }

        changes += "<div id=applying>Changing <span class=oldValue>'\(oldValue)'</span> to <span class=newValue>'\(newValue)'</span>...<div>"
        appendSource(title: "", text: "\(modifications) modifications proposed")
    }

    func writeChanges( dict: [String:NSData], header: String ) {
        setChangesSource(header: header, isApply: true)
        for (path, data) in dict {
            let wrote = data.write(toFile: path, atomically: true)
            appendSource(title: path, text: "\(wrote ? "Wrote" : "Could not write to") \(path)\n")
        }

        let indexUpdateTime = 5.0
        appendSource(title: "", text: "\nRefreshing in \(indexUpdateTime) seconds\n")
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + indexUpdateTime) {
            self.setup(target: self.history.last ?? self.defaultEntity())
        }

        formatter = Formatter()
        modified.removeAll()
        changes = ""
    }

    func searchProject(sender: AnyObject) {
        let pattern = sender is NSMenuItem ? replacement.stringValue : findText.stringValue
        setChangesSource(header: "USR search for pattern: \(pattern)")
        guard let indexDB = project?.indexDB else {
            xcode.error("Could load load index db \(project!.indexPath)")
            return
        }

        replacement.stringValue = pattern
        oldValue = pattern
        wasSearch = true

        entitiesByFile = indexDB.entitiesFor(pattern: pattern)
    }

}
