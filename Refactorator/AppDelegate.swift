//
//  AppDelegate.swift
//  Refactorator
//
//  Created by John Holdsworth on 19/11/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//
//  http://johnholdsworth.com/refactorator.html
//

import Cocoa
import WebKit

var xcode: AppDelegate!

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                WebUIDelegate, WebFrameLoadDelegate, WebPolicyDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var findPanel: NSPanel!

    @IBOutlet weak var sourceView: WebView!
    @IBOutlet weak var changesView: WebView!
    weak var printWebView: WebView!

    @IBOutlet weak var replacement: NSTextField!
    @IBOutlet weak var findText: NSTextField!

    @IBOutlet weak var applyButton: NSButton!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var revertButton: NSButton!

    @IBOutlet var backButton: NSMenuItem!
    @IBOutlet var forwardButton: NSMenuItem!
    @IBOutlet var reloadButton: NSMenuItem!

    var history = [Entity]()
    var future = [Entity]()
    var project: Project?

    var html = "", oldValue = "", changes = ""
    var saved = false

    var licensed: Bool {
        return UserDefaults.standard.string(forKey: colorKey) == myColor
    }

    func log( _ msg: String ) {
        appendSource(title: "", text: "<div class=log>\(msg)</div>")
        Swift.print( msg )
    }

    func error( _ msg: String ) {
        window.title = msg
        log( "<div class=error>\(msg)</div>" )
    }

    @objc func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        history = NSDocumentController.shared().recentDocumentURLs.reversed().map { Entity( file: $0.path ) }

        xcode = self
        if project == nil {
            setup()
        }

        let defaults = UserDefaults.standard, countKey = "n"
        let count = max(0,defaults.integer(forKey: countKey))+1
        defaults.set(count, forKey: countKey)
    }

    @IBAction func help(sender: NSMenuItem!) {
        NSWorkspace.shared().open(URL(string:"http://johnholdsworth.com/refactorator.html?index=\(myIndex)")!)
    }

    @IBAction func donate(sender: NSMenuItem!) {
        NSWorkspace.shared().open(URL(string:"http://johnholdsworth.com/cgi-bin/refactorator.cgi?index=\(myIndex)")!)
    }

    @objc func application(_ theApplication: NSApplication, openFile filename: String ) -> Bool {
        setup(target: Entity(file: filename))
        return true
    }

    @objc func refactorator(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        _ = pboard.string(forType: NSPasteboardTypeString)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        setup()
    }

    @objc func refactorFile(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        let options = [NSPasteboardURLReadingFileURLsOnlyKey:true]
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: options) {
            setup(target: Entity(file: (fileURLs[0] as! NSURL).path!))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    @objc func applicationDidUnhide(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
    }

    @objc func applicationWillBecomeActive(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
    }

    @IBAction func syncToXcode(sender: NSMenuItem) {
        setup()
    }

    @IBAction func open(sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.begin { (result) -> Void in
            if result == NSFileHandlingPanelOKButton,
                let url = panel.url {
                self.setup(target: Entity(file: url.path))
            }
        }
    }

    @IBAction func openInXcode(sender: NSMenuItem) {
        if let current = history.last {
            NSWorkspace.shared().open(current.file.url)
        }
    }

    @IBAction func openWorkspace(sender: NSMenuItem) {
        if let workspace = project?.workspacePath {
            NSWorkspace.shared().open(workspace.url)
        }
    }

    @IBAction func back(sender: NSMenuItem) {
        if !history.isEmpty {
            future.append( history.removeLast() )
            let save = future
            if !history.isEmpty {
                let previous = history.removeLast()
                setup(target: previous, cascade: false)
            }
            else {
                let recentSources = NSDocumentController.shared().recentDocumentURLs
                if recentSources.count > 1 {
                    setup(target: Entity(file: recentSources[1].path))
                }
            }
            future = save
        }
    }

    @IBAction func forward(sender: NSMenuItem) {
        if !future.isEmpty {
            setup(target: future.removeLast())
        }
    }

    @IBAction func reload(sender: NSMenuItem) {
        if let current = history.last {
            setup(target: Entity(file: current.file))
        }
    }
    
    @IBAction func printSource(sender: NSMenuItem) {
        let pi = NSPrintInfo.shared()
        pi.topMargin = 50
        pi.leftMargin = 25
        pi.rightMargin = 25
        pi.bottomMargin = 50
        pi.isHorizontallyCentered = false
        NSPrintOperation(view:printWebView.mainFrame.frameView.documentView, printInfo:pi).run()
    }

    @IBAction func zapDerivedData(sender: NSMenuItem) {
        let dir = HOME + "/Library/Developer/Xcode/DerivedData"
        let alert = NSAlert()
        alert.messageText = "Refactorator"
        alert.informativeText = "This will \"rm -rf\" the contents of Xcode's DerivedData directory: \(dir). There are rare times when this can be a good idea."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "I know what I'm doing")
        if alert.runModal() == NSAlertSecondButtonReturn {
            _system("/bin/rm -rf \"\(dir)\"")
        }
    }

    @IBAction func undoChanges(sender: AnyObject) {
        modified.removeAll()
        changes = ""
    }

    func defaultEntity() -> Entity {
        if let recentSource = NSDocumentController.shared().recentDocumentURLs.first {
            let entity = Entity(file: recentSource.path)
            project = Project(target: entity)
            return entity
        }
        return Entity(file: Bundle.main.path(forResource: "Intro", ofType: "html")!)
    }

    func sourceHTML() -> String {
        let path = Bundle.main.path(forResource: "Source", ofType: "html")!
        return try! String(contentsOfFile: path, encoding:.utf8)
    }

    func setup( target: Entity? = nil, cascade: Bool = true ) {
        let code = sourceHTML()
        if project == nil {
            changesView.uiDelegate = self
            changesView.mainFrame.loadHTMLString(code+"<div>Click on a symbol to locate references to rename</div>", baseURL: nil)
            changesView.policyDelegate = self
        }

        isTTY = false
        project = Project(target: target)
        let target = target ?? project?.entity ?? defaultEntity()

        printWebView = sourceView
        setLocation(entity: target)
        future.removeAll()

        if let sourceData = NSData(contentsOfFile: target.file) {
            if target.sourceName == "Intro.html" {
                html = String(data:sourceData as Data, encoding:.utf8)!
            }
            else {
                let entities = project?.indexDB?.entitiesFor(filePath: target.file)
                html = htmlFor(path: target.file, data: sourceData, entities: entities,
                               selecting: target, cascade: cascade, fullpath: false).joined()
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

    @objc override func validateMenuItem(_ aMenuItem: NSMenuItem) -> Bool {
        if let action = aMenuItem.action {
            switch action {
            case #selector(back(sender:)):
                return !history.isEmpty
            case #selector(forward(sender:)):
                return !future.isEmpty
            case #selector(openWorkspace(sender:)):
                return project?.workspacePath != Project.unknown
            case #selector(undoChanges(sender:)):
                fallthrough
            case #selector(saveChanges(sender:)):
                return !modified.isEmpty
            case #selector(revertSession(sender:)):
                return !originals.isEmpty && saved
            case #selector(buildProject(sender:)):
                return project?.workspaceDoc != nil
            case #selector(indexRebuild(sender:)):
                return project?.projectRoot != Project.unknown
            case #selector(buildSite(sender:)):
                return project?.indexDB != nil
            default:
                break
            }
        }
        return true
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

    let newline = CChar("\n".utf16.last!)

    func htmlFor( path: String, data: NSData, entities: [Entity]? = nil, skew: Int = 0, selecting: Entity? = nil, cascade: Bool = true, shortform: Bool = false, fullpath: Bool = true,
                  linker: @escaping (_ text: String, _ entity: Entity?) -> String = {
            (_ text: String, _ entity: Entity?) -> String in
            return text
        } ) -> [String] {

        var ptr = 0, skewtotal = 0, line = 1, col = 1, entityNumber = 0, html = ""
        let sourceBytes = data.bytes.assumingMemoryBound(to: CChar.self)

        func skipTo( offset: Int ) -> (text: String, entity: Entity?) {
            if offset <= ptr {
                return ("", nil)
            }

            let selectedByOffset = ptr == selecting?.offset
            var offset = offset + skewtotal
            var currentEntity: Entity?

            if let entities = entities, entityNumber < entities.count {
                var entity = entities[entityNumber]
                while (entity.line < line || entity.line == line && entity.col < col) && entityNumber + 1 < entities.count {
//                    xcode.log("Missed entity \(entity.line):\(entity.col) < \(line):\(col) \(entity.usr) - \(path)")
                    entityNumber += 1
                    entity = entities[entityNumber]
                }
                if entity.line == line && entity.col == col || entity.offset == ptr+skewtotal {
//                    xcode.log("entity \(entity.line):\(entity.col) == \(line):\(col) \(entity.usr) - \(path)")
                    currentEntity = entity
                    entityNumber += 1
                    if !entity.notMatch {
                        offset += skew
                    }
                }
            }

            let out = NSString( bytes: sourceBytes+ptr+skewtotal,
                                length: offset-(ptr+skewtotal),
                                encoding: String.Encoding.utf8.rawValue ) ??
                        NSString( bytes: sourceBytes+ptr+skewtotal,
                                  length: offset-(ptr+skewtotal),
                                  encoding: String.Encoding.isoLatin1.rawValue ) ??
                        "?\(ptr+skewtotal)?\(offset-(ptr+skewtotal))?" as NSString

            while ptr+skewtotal < offset {
                if sourceBytes[ptr+skewtotal] == newline {
                    line += 1
                    col = 1
                }
                else {
                    col += 1
                }
                ptr += 1
            }

            if currentEntity?.notMatch == false {
                skewtotal += skew
                ptr -= skew
            }
//            ptr = offset-skews

            var escaped = htmlEscape( out as String )
            if currentEntity?.decl == true {
                escaped = "<span class=declaration>\(escaped)</span>"
            }
            if selectedByOffset || currentEntity != nil && (currentEntity == selecting || selecting == nil) {
                escaped = "<span class=highlighted id=selected cascade=\(cascade ? 1 : 0)>\(escaped)</span>"
            }

            return (escaped, currentEntity)
        }


        let sourceKit = Project.sourceKit
        let cleanPath = fullpath ? path : relative( path )
        let resp = project?.maps[path] ?? sourceKit.syntaxMap(filePath: path)
        project?.maps[path] = resp

        let dict = sourcekitd_response_get_value( resp )
        let map = sourcekitd_variant_dictionary_get_value( dict, sourceKit.syntaxID )
        sourcekitd_variant_array_apply( map ) { (_,dict) in
            let kind = dict.getUUIDString( key: sourceKit.kindID )
            let offset = dict.getInt( key: sourceKit.offsetID )
            let length = dict.getInt( key: sourceKit.lengthID )
            let kindSuffix = kind .url.pathExtension

            html += skipTo( offset: offset ).text

            var span = "<span"
            if !shortform {
                span += " line=\(line) col=\(col) offset=\(ptr) title=\"\(cleanPath)#\(line):\(col)"
            }

            var (text, entity) = skipTo( offset: offset+length )
            let type = entity != nil ? "Xc\(entity!.kindSuffix) " : ""
            let usr = entity?.usr != nil ? htmlEscape( demangle( entity!.usr! )! ) : ""

            if !shortform {
                span += " \(usr) \(entity?.kind ?? "")\""
            }

            span += " class='\(type)\(kindSuffix)' entity=\(entity != nil || entities == nil ? 1 : 0)>"

            if kindSuffix == "url" {
                text = "<a href=\"\(text)\">\(text)</a>"
            }
            html += "\(span)\(linker(text, entity))</span>"

            return true
        }
        
        html += skipTo( offset: data.length-skewtotal ).0

        var lineNumber = 0
        let lines = html.components(separatedBy: "\n").map {
            (line) -> String in
            lineNumber += 1
            return String(format:"<span class=linenumber>%04d&nbsp;</span>", lineNumber)+line+"\n"
        }

        return lines
    }

    func relative( _ path: String ) -> String {
        return project != nil ? path
            .replacingOccurrences(of: project!.projectRoot+"/", with: "")
            .replacingOccurrences(of: HOME+"/", with: "") : path
    }

    @objc func webView( _ webView: WebView, addMessageToConsole message: NSDictionary ) {
        Swift.print("\(message)")
    }

    @objc func webView(_ sender: WebView!, runJavaScriptAlertPanelWithMessage message: String!, initiatedBy frame: WebFrame!) {
        print("\(message)")
    }

    @objc func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        if sender == sourceView {
            sourceView.policyDelegate = self
            let win = sourceView.windowScriptObject!
            win.setValue(self, forKey:"appDelegate")
            win.callWebScriptMethod("setSource", withArguments: [html])
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
        return [backButton, forwardButton, reloadButton]
    }

    var entitiesByFile = [[Entity]]()
    var originals = [String:NSData]()
    var modified = [String:NSData]()
    var linecounts = [String:Int]()

    @discardableResult
    func setChangesSource( header: String? = nil, target: Entity? = nil, isApply: Bool = false ) -> WebScriptObject {
        if !isApply {
            project = Project(target: target ?? history.last)
        }
        let win = changesView.windowScriptObject!
        win.callWebScriptMethod("setSource", withArguments: [header != nil ? "<div class=changesHeader>\(header!)</div>" : ""])
        if project?.indexDB == nil {
            xcode.error("No index DB found for project: \(project?.workspacePath ?? "unavailable")")
        }
        return win
    }

    func appendSource( title: String, text: String ) {
        changesView.windowScriptObject.callWebScriptMethod("appendSource", withArguments: [title, text])
    }
    
    @objc override class func isSelectorExcluded( fromWebScript aSelector: Selector ) -> Bool {
        return aSelector != #selector(selected(text:title:line:col:offset:metaKey:)) &&
            aSelector != #selector(changeSelected(text:title:line:col:offset:metaKey:))
    }

    @objc public func selected( text: String, title: String, line: Int, col: Int, offset: Int, metaKey: Bool ) {
        let entity = Entity(file: history.last?.file ?? title.components(separatedBy: "#")[0],
                            line: line, col: col, offset: offset)

        setChangesSource(target: entity).setValue(self, forKey:"appDelegate2")
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
            if let usr = indexDB.usrInFile(filePath: sourcePath, line: line, col: col) {

                if metaKey, let entity = indexDB.declarationFor(filePath: sourcePath, line: line, col: col) {
                    setup(target: entity, cascade: false)
                    return
                }

                setLocation(entity: entity)

                appendSource(title: project!.indexPath, text: "<div class=usr>USR: <span title=\"\(usr)\">\(htmlEscape( demangle( usr )! ))</span></div>")

                var system = false
                var pathSeen = [String:Int]()
                _ = indexDB.entitiesFor(filePath: sourcePath, line: line, col: col) {
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
                        return
                    }

                    entitiesByFile.append( entities )
                }

//                entitiesByFile.sort(by: { $0.0.filter { $0.decl }.count != 0 })
                processEntities(type: "references")
                if system {
                    appendSource(title: "", text: "\nToolchain symbol")
                }
            }
            else {
                xcode.log("<span title=\"\(project?.indexPath ?? "")\">No USR associated with \(entity.sourceName)#\(line):\(col) in project: \(project!.workspaceName). Is indexing complete?</span>")
                _system("touch \"\(entity.file)\"")
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
        let body = entities.map { lines[$0.line-1] }.joined()
        return "<a class=sourceLink href=\"file:\(path)\">\(filename)</a>\n<div class='changesEntry'>\(body)</div>"
    }

    var wasSearch = false

    @IBAction func applySubstitution(sender: NSButton) {
        let newValue = replacement.stringValue
        if newValue == myColor && !licensed {
            setChangesSource(header: "<div class=licensed>You are now licensed. Thanks!</div><br><img src='data:image/png;base64,\(fireworks)'>", isApply: true)
            UserDefaults.standard.set(newValue, forKey: colorKey)
            UserDefaults.standard.synchronize()
            return
        }

        if oldValue == "" {
            setChangesSource(header: "Please select an entity before applying replacement", isApply: true)
            return
        }

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

                let lines = htmlFor(path: path, data: out, entities: entities, skew: skew)
                appendSource(title: path, text: filtered(lines, entities))
                if lines.count != linecounts[path] {
                    xcode.log("Mismatched linecount \(lines.count) != \(linecounts[path]) for \(path)")
                }
            }
        }

        changes += "<div id=applying>Changing <span class=oldValue>'\(oldValue)'</span> to <span class=newValue>'\(newValue)'</span>...<div>"
        appendSource(title: "", text: "\(modifications) modifications proposed")
        revertButton.isEnabled = !originals.isEmpty
        saveButton.isEnabled = !modified.isEmpty
        oldValue = newValue
    }

    func processEntities(type: String) {
        var changes = 0, files = 0

        for entities in entitiesByFile.sorted( by: { $0[0].file < $1[0].file } ) {
            let path = entities[0].file
            if let sourceData = NSData(contentsOfFile: path) {
                let lines = htmlFor(path: path, data: sourceData, entities: entities)
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

    @IBAction func openFind(sender: NSMenuItem) {
        if findText.stringValue == "" {
            findText.stringValue = replacement.stringValue
        }
        findPanel.makeKeyAndOrderFront(nil)
    }

    @IBAction func findInSource(sender: AnyObject) {
        let string = findText.stringValue
        switch sender.tag {
        case 1:
            fallthrough
        case 2:
            sourceView.search( for: string, direction:true, caseSensitive:false, wrap:true)
        case 3:
            sourceView.search( for: string, direction:false, caseSensitive:false, wrap:true)
        default:
            break
        }
    }

    @IBAction func searchProject(sender: AnyObject) {
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
        processEntities(type: sender is AppDelegate ? "errors" : "references")
    }
    
    @IBAction func findOrphans(sender: NSMenuItem) {
        setChangesSource(header: "Symbols declared but not referred to...")
        guard let indexDB = project?.indexDB else {
            xcode.error("Could load load index db \(project!.indexPath)")
            return
        }

        entitiesByFile = indexDB.orphans()
        processEntities(type: "orphans")
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

        modified.removeAll()
        changes = ""
    }

    @IBAction func saveChanges(sender: AnyObject) {
        writeChanges(dict: modified, header: changes)
        saved = true
    }

    @IBAction func buildProject(sender: AnyObject) {
        _ = project?.workspaceDoc?.build()
    }

    @IBAction func revertSession(sender: AnyObject) {
        writeChanges(dict: originals, header: "Reverting changes...\n")
        undoChanges(sender: self)
    }

    @IBAction func indexCheck(sender: NSMenuItem) {
        findText.stringValue = "ERROR TYPE"
        searchProject(sender: self)
    }

    @IBAction func indexRebuild(sender: NSMenuItem) {
        _system("find \"\(project!.projectRoot)\" -name '*.swift' -exec touch {} \\;")
    }

    @IBAction func exportHTML(sender: NSMenuItem) {
        let out = sourceView.windowScriptObject.evaluateWebScript("document.head.outerHTML + document.body.outerHTML") as! String
        let panel = NSSavePanel()
        panel.nameFieldStringValue = history.last!.file.url.deletingPathExtension().lastPathComponent+".html"
        panel.begin { (result) -> Void in
            if result == NSFileHandlingPanelOKButton,
                let url = panel.url {
                try? out.write(to: url, atomically: false, encoding: .utf8)
            }
        }
    }

    @IBAction func buildSite(sender: AnyObject) {
        guard let projectRoot = project?.projectRoot else { return }
        let htmlDir = projectRoot+"/html/"
        setChangesSource(header: "Building source site into \(htmlDir)")
        try? FileManager.default.createDirectory(atPath: htmlDir, withIntermediateDirectories: false, attributes: nil)
        if var entiesForFiles = project?.indexDB?.projectEntities() {
            var referencesByUSR = [Int:[Entity]]()
            var declarationsByUSR = [Int:Entity]()

            var dataByFile = [String:NSData]()
            var linesByFile = [String:[String]]()

            for entities in entiesForFiles {
                for entity in entities {
                    if let usrID = entity.usrID {
                        if referencesByUSR[usrID] == nil {
                            referencesByUSR[usrID] = [Entity]()
                        }
                        referencesByUSR[usrID]!.append(entity)
                        if entity.decl {
                            declarationsByUSR[usrID] = entity
                        }
                    }
                }
                let path = entities[0].file

                dataByFile[path] = NSData(contentsOfFile: path)
                linesByFile[path] = htmlFor(path: path, data: dataByFile[path]!, entities: entities, shortform: true, fullpath: false )
            }

            for (usrID, _) in referencesByUSR {
                referencesByUSR[usrID]!.sort { $0.0 < $0.1 }
            }

            func htmlFile( _ path: String ) -> String {
                return relative( path ).replacingOccurrences(of: "/", with: "_") + ".html"
            }

            func href( _ entity: Entity ) -> String {
                return "\(htmlFile(entity.file))#L\(entity.line)"
            }

            let common = sourceHTML()

            let siteThreads = 4, threadPool = DispatchGroup()

            for threadNumber in 0..<siteThreads {
                threadPool.enter()
                DispatchQueue.global().async {
                    for fileNumber in stride(from: threadNumber,
                                        through: entiesForFiles.count-1, by: siteThreads) {
                        let entities = entiesForFiles[fileNumber]
                        let path = entities[0].file
                        let out = common + self.htmlFor(path: path, data: dataByFile[path]!, entities: entities, selecting: Entity(file:""), fullpath: false ) {
                            (text, entity) -> String in
                            var text = text
                            if let entity = entity,
                                let decl = declarationsByUSR[entity.usrID!],
                                let related = referencesByUSR[entity.usrID!] {
                                if related.count > 1 {
                                    if entity.decl || self.project?.indexDB?.podDirIDs[entity.dirID] == nil {
                                        var popup = ""
                                        for ref in related {
                                            if ref == entity {
                                                continue
                                            }
                                            let keepListOpen = ref.file != decl.file ? "event.stopPropagation(); " : ""
                                            popup += "<tr\(ref == decl ? " class=decl" : "")><td style='text-decoration: underline;' " +
                                            "onclick='document.location.href=\"\(href(ref))\"; \(keepListOpen)return false;'>\(ref.file.url.lastPathComponent)</td>"
                                            popup += "<td><pre>\(linesByFile[ref.file]![ref.line-1].replacingOccurrences(of: "\n", with: ""))</pre></td>"
                                        }
                                        text = "<a style='color: inherit' name='L\(entity.line)' href='\(href(decl))' target=_self onclick='return expand(this, event.metaKey);'>" +
                                        "\(text)<span class='references'><table>\(popup)</table></span></a>"
                                    }
                                    else {
                                        text = "<a style='color: inherit' href='\(href(decl))'>\(text)</a>"
                                    }
                                }
                                else if entity.decl == true {
                                    text = "<a style='color: inherit' name='L\(entity.line)' no_href='\(href(decl))'>\(text)</a>"
                                }
                            }
                            return text
                            }.joined()

                        let final = htmlDir.url.appendingPathComponent(htmlFile(path))
                        try? out.write(to: final, atomically: false, encoding: .utf8)
                        DispatchQueue.main.async {
                            self.appendSource(title: "", text: "Wrote <a href=\"file://\(final.path)\">\(final.path)</a>\n")
                        }
                    }

                    threadPool.leave()
                }
            }

            threadPool.wait()

            var sources = common+"</pre><div class=filelist><h2>Sources for Project \(project?.workspaceName ?? "")</h2>"

            for entities in entiesForFiles.sorted(by: { $0.0[0].file < $0.1[0].file }) {
                let path =  entities[0].file
                sources += "<a href='\(htmlFile(path))'>\(relative(path))</a><br>"
            }

            let index = htmlDir+"index.html"
            try? sources.write(toFile: index, atomically: false, encoding: .utf8)
            NSWorkspace.shared().open(index.url)
        }
    }

}

func htmlEscape( _ str: String ) -> String {
    return str.replacingOccurrences( of: "&", with: "&amp;" ).replacingOccurrences( of:"<", with: "&lt;" )
}

//    ["AliceBlue", "AntiqueWhite", "Aqua", "Aquamarine", "Azure", "Beige", "Bisque", "Black", "BlanchedAlmond", "Blue", "BlueViolet", "Brown", "BurlyWood", "CadetBlue", "Chartreuse", "Chocolate", "Coral", "CornflowerBlue", "Cornsilk", "Crimson", "Cyan", "DarkBlue", "DarkCyan", "DarkGoldenRod", "DarkGray", "DarkGrey", "DarkGreen", "DarkKhaki", "DarkMagenta", "DarkOliveGreen", "DarkOrange", "DarkOrchid", "DarkRed", "DarkSalmon", "DarkSeaGreen", "DarkSlateBlue", "DarkSlateGray", "DarkSlateGrey", "DarkTurquoise", "DarkViolet", "DeepPink", "DeepSkyBlue", "DimGray", "DimGrey", "DodgerBlue", "FireBrick", "FloralWhite", "ForestGreen", "Fuchsia", "Gainsboro", "GhostWhite", "Gold", "GoldenRod", "Gray", "Grey", "Green", "GreenYellow", "HoneyDew", "HotPink", "IndianRed", "Indigo", "Ivory", "Khaki", "Lavender", "LavenderBlush", "LawnGreen", "LemonChiffon", "LightBlue", "LightCoral", "LightCyan", "LightGoldenRodYellow", "LightGray", "LightGrey", "LightGreen", "LightPink", "LightSalmon", "LightSeaGreen", "LightSkyBlue", "LightSlateGray", "LightSlateGrey", "LightSteelBlue", "LightYellow", "Lime", "LimeGreen", "Linen", "Magenta", "Maroon", "MediumAquaMarine", "MediumBlue", "MediumOrchid", "MediumPurple", "MediumSeaGreen", "MediumSlateBlue", "MediumSpringGreen", "MediumTurquoise", "MediumVioletRed", "MidnightBlue", "MintCream", "MistyRose", "Moccasin", "NavajoWhite", "Navy", "OldLace", "Olive", "OliveDrab", "Orange", "OrangeRed", "Orchid", "PaleGoldenRod", "PaleGreen", "PaleTurquoise", "PaleVioletRed", "PapayaWhip", "PeachPuff", "Peru", "Pink", "Plum", "PowderBlue", "Purple", "RebeccaPurple", "Red", "RosyBrown", "RoyalBlue", "SaddleBrown", "Salmon", "SandyBrown", "SeaGreen", "SeaShell", "Sienna", "Silver", "SkyBlue", "SlateBlue", "SlateGray", "SlateGrey", "Snow", "SpringGreen", "SteelBlue", "Tan", "Teal", "Thistle", "Tomato", "Turquoise", "Violet", "Wheat", "White", "WhiteSmoke", "Yellow", "YellowGreen"]

private let myIndex = {
    () -> Int in
    var index = 0
    if var chars = getenv("USER") {
        while chars.pointee != 0 {
            index += Int(chars.pointee)
            chars += 1
        }
    }
    return index
}()

private let myColor = {
    () -> String in
    return colors[myIndex % colors.count]
}()

private let colorKey = "Color"

private let colors = String(data: Data(base64Encoded: "QWxpY2VCbHVlOkFudGlxdWVXaGl0ZTpBcXVhOkFxdWFtYXJpbmU6QXp1cmU6QmVpZ2U6QmlzcXVlOkJsYWNrOkJsYW5jaGVkQWxtb25kOkJsdWU6Qmx1ZVZpb2xldDpCcm93bjpCdXJseVdvb2Q6Q2FkZXRCbHVlOkNoYXJ0cmV1c2U6Q2hvY29sYXRlOkNvcmFsOkNvcm5mbG93ZXJCbHVlOkNvcm5zaWxrOkNyaW1zb246Q3lhbjpEYXJrQmx1ZTpEYXJrQ3lhbjpEYXJrR29sZGVuUm9kOkRhcmtHcmF5OkRhcmtHcmV5OkRhcmtHcmVlbjpEYXJrS2hha2k6RGFya01hZ2VudGE6RGFya09saXZlR3JlZW46RGFya09yYW5nZTpEYXJrT3JjaGlkOkRhcmtSZWQ6RGFya1NhbG1vbjpEYXJrU2VhR3JlZW46RGFya1NsYXRlQmx1ZTpEYXJrU2xhdGVHcmF5OkRhcmtTbGF0ZUdyZXk6RGFya1R1cnF1b2lzZTpEYXJrVmlvbGV0OkRlZXBQaW5rOkRlZXBTa3lCbHVlOkRpbUdyYXk6RGltR3JleTpEb2RnZXJCbHVlOkZpcmVCcmljazpGbG9yYWxXaGl0ZTpGb3Jlc3RHcmVlbjpGdWNoc2lhOkdhaW5zYm9ybzpHaG9zdFdoaXRlOkdvbGQ6R29sZGVuUm9kOkdyYXk6R3JleTpHcmVlbjpHcmVlblllbGxvdzpIb25leURldzpIb3RQaW5rOkluZGlhblJlZDpJbmRpZ286SXZvcnk6S2hha2k6TGF2ZW5kZXI6TGF2ZW5kZXJCbHVzaDpMYXduR3JlZW46TGVtb25DaGlmZm9uOkxpZ2h0Qmx1ZTpMaWdodENvcmFsOkxpZ2h0Q3lhbjpMaWdodEdvbGRlblJvZFllbGxvdzpMaWdodEdyYXk6TGlnaHRHcmV5OkxpZ2h0R3JlZW46TGlnaHRQaW5rOkxpZ2h0U2FsbW9uOkxpZ2h0U2VhR3JlZW46TGlnaHRTa3lCbHVlOkxpZ2h0U2xhdGVHcmF5OkxpZ2h0U2xhdGVHcmV5OkxpZ2h0U3RlZWxCbHVlOkxpZ2h0WWVsbG93OkxpbWU6TGltZUdyZWVuOkxpbmVuOk1hZ2VudGE6TWFyb29uOk1lZGl1bUFxdWFNYXJpbmU6TWVkaXVtQmx1ZTpNZWRpdW1PcmNoaWQ6TWVkaXVtUHVycGxlOk1lZGl1bVNlYUdyZWVuOk1lZGl1bVNsYXRlQmx1ZTpNZWRpdW1TcHJpbmdHcmVlbjpNZWRpdW1UdXJxdW9pc2U6TWVkaXVtVmlvbGV0UmVkOk1pZG5pZ2h0Qmx1ZTpNaW50Q3JlYW06TWlzdHlSb3NlOk1vY2Nhc2luOk5hdmFqb1doaXRlOk5hdnk6T2xkTGFjZTpPbGl2ZTpPbGl2ZURyYWI6T3JhbmdlOk9yYW5nZVJlZDpPcmNoaWQ6UGFsZUdvbGRlblJvZDpQYWxlR3JlZW46UGFsZVR1cnF1b2lzZTpQYWxlVmlvbGV0UmVkOlBhcGF5YVdoaXA6UGVhY2hQdWZmOlBlcnU6UGluazpQbHVtOlBvd2RlckJsdWU6UHVycGxlOlJlYmVjY2FQdXJwbGU6UmVkOlJvc3lCcm93bjpSb3lhbEJsdWU6U2FkZGxlQnJvd246U2FsbW9uOlNhbmR5QnJvd246U2VhR3JlZW46U2VhU2hlbGw6U2llbm5hOlNpbHZlcjpTa3lCbHVlOlNsYXRlQmx1ZTpTbGF0ZUdyYXk6U2xhdGVHcmV5OlNub3c6U3ByaW5nR3JlZW46U3RlZWxCbHVlOlRhbjpUZWFsOlRoaXN0bGU6VG9tYXRvOlR1cnF1b2lzZTpWaW9sZXQ6V2hlYXQ6V2hpdGU6V2hpdGVTbW9rZTpZZWxsb3c6WWVsbG93R3JlZW4=")!, encoding: .utf8 )!.components(separatedBy: ":")

private var fireworks = "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"
