//
//  Formatter.swift
//  Refactorator
//
//  Created by John Holdsworth on 13/12/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Foundation
import WebKit

protocol AppGui: AppLogging {

    var project: Project? { get }
    func sourceHTML() -> String
    func setChangesSource( header: String?, target: Entity?, isApply: Bool )
    func appendSource( title: String, text: String )
    func relative( _ path: String ) -> String
    func open( url: String )

}

class Formatter {

    static let sourceKit = SourceKit()

    var maps = [String:(mtime: TimeInterval, resp: sourcekitd_response_t)]()
    let newline = CChar("\n".utf16.last!)

    func htmlFor( path: String, data: NSData, entities: [Entity]? = nil, skew: Int = 0, selecting: Entity? = nil, cascade: Bool = true, shortform: Bool = false, cleanPath: String? = nil, coverage: Set<Int>? = nil,
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

        isTTY = false

        let sourceKit = Formatter.sourceKit
        let cleanPath = cleanPath ?? path
        let modified = mtime( path )
        let resp = (modified == maps[path]?.mtime ? maps[path]?.resp : nil) ?? sourceKit.syntaxMap(filePath: path)
        maps[path] = (modified,resp)

        var extensions = [String:String]()

        let dict = SKApi.sourcekitd_response_get_value( resp )
        let map = SKApi.sourcekitd_variant_dictionary_get_value( dict, sourceKit.syntaxID )
        _ = SKApi.sourcekitd_variant_array_apply( map ) { (_,dict) in
            let kind = dict.getUUIDString( key: sourceKit.kindID )
            let offset = dict.getInt( key: sourceKit.offsetID )
            let length = dict.getInt( key: sourceKit.lengthID )
            let kindSuffix = extensions[kind] ?? kind.url.pathExtension
            if extensions[kind] == nil {
                extensions[kind] = kindSuffix
            }

            html += skipTo( offset: offset ).text

            var span = "<span"
            if !shortform {
                span += " line=\(line) col=\(col) offset=\(ptr) title=\"\(cleanPath)#\(line):\(col)"
            }

            var (text, entity) = skipTo( offset: offset+length )
            let type = entity != nil ? "Xc\(entity!.kindSuffix) " : ""
            let usr = entity?.usr != nil ? htmlEscape( demangle( entity!.usr! ) ) : ""

            if !shortform {
                span += " \(usr) \(entity?.kind ?? "") \(entity?.role ?? -1)\""
            }

            span += " class='\(type)\(kindSuffix)' entity=\(entity != nil || entities == nil ? 1 : 0)>"

            if kindSuffix == "url" {
                text = "<a href=\"\(text)\">\(text)</a>"
            }
            html += "\(span)\(linker(text, entity))</span>"

            return true
        }

        html += skipTo( offset: data.length-skewtotal ).0

        var lineno = 0
        let lines = html.components(separatedBy: "\n").map {
            (line) -> String in
            lineno += 1
            var classes = "linenumber"
            if coverage?.contains(lineno) == true {
                classes += " covered"
            }
            return String(format:"<span class='\(classes)' id=L\(lineno)>%04d&nbsp;</span>", lineno)+line+"\n"
        }
        
        return lines
    }

    func htmlFile(_ state: AppGui, _ path: String ) -> String {
        return state.relative( path ).replacingOccurrences(of: "/", with: "_") + ".html"
    }

    func buildSite( for project: Project, into htmlDir: String, state: AppGui ) {
        state.setChangesSource(header: "Building source site into \(htmlDir)", target: nil, isApply: false)

        try? FileManager.default.createDirectory(atPath: htmlDir, withIntermediateDirectories: false, attributes: nil)
        if var entiesForFiles = project.indexDB?.projectEntities() {
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
            }

            DispatchGroup.inParallel(work: entiesForFiles) {
                (entities, locked) in
                let path = entities[0].file
                let data = NSData(contentsOfFile: path) ?? NSData()
                let html = self.htmlFor(path: path, data: data, entities: entities, shortform: true)
                locked {
                    dataByFile[path] = data
                    linesByFile[path] = html
                }
            }

            for (usrID, _) in referencesByUSR {
                referencesByUSR[usrID]!.sort { $0.0 < $0.1 }
            }

            func href( _ entity: Entity ) -> String {
                return "\(htmlFile(state, entity.file))#L\(entity.line)"
            }

            let common = state.sourceHTML()

            DispatchGroup.inParallel(work: entiesForFiles) {
                (entities, locked) in
                let path = entities[0].file
                let out = common + self.htmlFor(path: path, data: dataByFile[path]!, entities: entities, selecting: Entity(file:""), cleanPath: state.relative(path) ) {
                    (text, entity) -> String in
                    var text = text
                    if let entity = entity,
                        let decl = declarationsByUSR[entity.usrID!],
                        let related = referencesByUSR[entity.usrID!] {
                        if related.count > 1 {
                            if entity.decl || state.project?.indexDB?.podDirIDs[entity.dirID] == nil {
                                var popup = ""
                                for ref in related {
                                    if ref == entity {
                                        continue
                                    }
                                    let keepListOpen = ref.file != decl.file ? "event.stopPropagation(); " : ""
                                    popup += "<tr\(ref == decl ? " class=decl" : "")><td style='text-decoration: underline;' " +
                                    "onclick='document.location.href=\"\(href(ref))\"; \(keepListOpen)return false;'>\(ref.file.url.lastPathComponent)</td>"
                                    let lines = linesByFile[ref.file] ?? []
                                    let reference = ref.line < lines.count ? lines[ref.line-1] : ""
                                    popup += "<td><pre>\(reference.replacingOccurrences(of: "\n", with: ""))</pre></td>"
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

                let final = htmlDir.url.appendingPathComponent(self.htmlFile(state, path))
                do {
                    try out.write(to: final, atomically: false, encoding: .utf8)
                    DispatchQueue.main.async {
                        state.appendSource(title: "", text: "Wrote <a href=\"file://\(final.path)\">\(final.path)</a>\n")
                    }
                }
                catch (let e) {
                    print("Could not save to \(final): \(e)")
                }
            }

            do {
                let workspace = state.project?.workspaceName ?? "unknown"
                var sources = common+"</pre><div class=filelist><h2>Sources for Project \(workspace)</h2><script> document.title = 'Sources for Project \(workspace)' </script>"
                
                for entities in entiesForFiles.sorted(by: { $0.0[0].file < $0.1[0].file }) {
                    let path =  entities[0].file
                    sources += "<a href='\(htmlFile(state, path))'>\(state.relative(path))</a><br>"
                }
                
                sources += "<p>Cross Reference can be found <a href='xref.html'>here</a>."
                sources += "<p>Dependencies Graph can be found <a href='canviz.html'>here</a>."
                let index = htmlDir+"index.html"
                try sources.write(toFile: index, atomically: false, encoding: .utf8)
                DispatchQueue.main.async {
                    state.appendSource(title: "", text: "Wrote <a href=\"file://\(index)\">\(index)</a>\n")
                }

                sources = common+"</pre><div class=filelist><h2>Symbols defined in \(workspace)</h2><script> document.title = 'Symbols defined in \(workspace)' </script>"
                
                for entity in declarationsByUSR.values.sorted(by: {demangle($0.0.usr)! < demangle($0.1.usr)!}) {
                    sources += "<a href='\(href(entity))'>\(htmlEscape( demangle(entity.usr) ))</a><br>"
                }
                
                let xref = htmlDir+"xref.html"
                try sources.write(toFile: xref, atomically: false, encoding: .utf8)
                DispatchQueue.main.async {
                    state.appendSource(title: "", text: "Wrote <a href=\"file://\(xref)\">\(xref)</a>\n")
                }

                state.open(url: index)

                runDepends(state: state, standalone: true)

                let dotFile = htmlDir+"refactorator.gv"
                try? FileManager.default.removeItem(atPath: dotFile)
                try FileManager.default.copyItem(atPath: gvfile, toPath: dotFile)

                let canviz = Bundle.main.path(forResource: "canviz-0.1", ofType: nil)!
                try? FileManager.default.copyItem(atPath: canviz, toPath: htmlDir+"canviz-0.1")

                let canviz2 = Bundle.main.path(forResource: "canviz2", ofType: "html")!
                try? FileManager.default.removeItem(atPath: htmlDir+"canviz.html")
                try FileManager.default.copyItem(atPath: canviz2, toPath: htmlDir+"canviz.html")
            }
            catch (let e) {
                state.error( "Error building site: \(e)")
            }
        }
    }

    var DOT_PATH = "/usr/local/bin/dot"
    var gvfile: String {
        return "/tmp/canviz.gv"
    }

    func runDepends( state: AppGui, standalone: Bool ) {
        var nodeID = 0, nodes = [String:Int]()
        var dot = "digraph xref {\n    node [fontname=\"Arial\"];\n"
        func defineNode( _ path: String ) -> String {
            if nodes[path] == nil {
                nodeID += 1
                nodes[path] = nodeID
                let label = path.hasSuffix(".swift") ?
                    path.url.deletingPathExtension().lastPathComponent : path.url.lastPathComponent
                dot += "N\(nodeID) [href=\"javascript:void(click_node('\(standalone ? htmlFile(state, path) : path)'))\" " +
                    "label=\"\(label)\" tooltip=\"\(state.relative(path))\"];\n"
            }
            return "N\(nodes[path]!)"
        }

        for (to, from, count) in state.project!.indexDB!.dependencies() {
            dot += "    \(defineNode( from )) -> \(defineNode( to )) [penwidth=\(log10(Double(count)))]\n"
        }

        dot += "}\n"

        let dotfile = "/tmp/refactorator.dot"
        try? dot.write(toFile: dotfile, atomically: false, encoding: .utf8)

        Process.run(path: DOT_PATH, args: [dotfile, "-Txdot", "-o"+gvfile])
    }

    func indexAssociations( filePath: String, state: AppGui ) {

        let logDir = state.project!.derivedData+"/Logs/Build"
        let xcodeBuildLogs = LogParser( logDir: logDir )

        guard let argv = xcodeBuildLogs.compilerArgumentsMatching( matcher: { line in
            line.contains( " -primary-file \(filePath) " ) ||
                line.contains( " -primary-file \"\(filePath)\" " ) } ) else {
                    xcode.error( "Could not find compiler arguments in \(logDir). Have you built all files in the project?" )
                    return
        }

        state.setChangesSource(header: "Re-indexing to capture associations between USRs", target: nil, isApply: false)

        DispatchQueue.global().async {
            let SK = Formatter.sourceKit
            var relatedUSRs = "", count = 0
            let files = argv.filter { $0.hasSuffix( ".swift" ) }
            let notRelated = "^source\\.lang\\.swift\\.decl\\.(extension\\.)?(class|struct|enum|protocol)$"
            let regexp = try! NSRegularExpression(pattern: notRelated, options: [])

            DispatchGroup.inParallel(work: files ) {
                (file, locked) in
                DispatchQueue.main.async {
                    state.appendSource(title: "", text: "Indexing \(file)\n")
                }

                var fileRelatedUSRs = [String]()
                let resp = SK.indexFile( filePath: file, compilerArgs: SK.array( argv: argv ) )
//                SKApi.sourcekitd_response_description_dump( resp )

                SK.recurseOver( childID: SK.entitiesID, resp: SKApi.sourcekitd_response_get_value( resp ) ) {
                    (entity) in
                    let related = SKApi.sourcekitd_variant_dictionary_get_value( entity, SK.relatedID )
                    if SKApi.sourcekitd_variant_get_type( related ) == SOURCEKITD_VARIANT_TYPE_ARRAY {
                        let kind = entity.getUUIDString(key: SK.kindID )
                        if regexp.firstMatch(in: kind, options: [], range: NSMakeRange(0, kind.utf16.count)) == nil,
                            let usr = entity.getString(key: SK.usrID) {
                            _ = SKApi.sourcekitd_variant_array_apply( related ) {
                                (_,dict) in
                                if let usr2 = dict.getString(key: SK.usrID) {
                                    fileRelatedUSRs.append( "\(usr)\t\(usr2)\n" )
                                }
                                return true
                            }
                        }
                    }
                }

                SKApi.sourcekitd_response_dispose( resp )

                let entry = "\(mtime(file))\t\(file)\n"+fileRelatedUSRs.joined()
                print( entry )

                if fileRelatedUSRs.count != 0 {
                    locked {
                        relatedUSRs += entry
                        count += fileRelatedUSRs.count
                    }
                }
            }

            if let relatedsPath = state.project?.indexDB?.relatedsDB {
                try? relatedUSRs.write(toFile: relatedsPath, atomically: true, encoding: .utf8)
            }

            DispatchQueue.main.async {
                state.appendSource(title: "", text: "\n<b>Indexing complete. \(count) associations found in \(files.count) files.</b>\n")
            }
        }
    }

    deinit {
        for (_, entry) in maps {
            SKApi.sourcekitd_request_release(entry.resp)
        }
    }

}
