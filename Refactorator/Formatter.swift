//
//  Formatter.swift
//  Refactorator
//
//  Created by John Holdsworth on 13/12/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Foundation

func htmlEscape( _ str: String ) -> String {
    return str.contains("<") || str.contains("&") ?
        str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;") : str
}

class Formatter {

    var maps = [String:sourcekitd_response_t]()
    let newline = CChar("\n".utf16.last!)

    func htmlFor( path: String, data: NSData, entities: [Entity]? = nil, skew: Int = 0, selecting: Entity? = nil, cascade: Bool = true, shortform: Bool = false, cleanPath: String? = nil,
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
        let cleanPath = cleanPath ?? path
        let resp = maps[path] ?? sourceKit.syntaxMap(filePath: path)
        maps[path] = resp

        var extensions = [String:String]()

        let dict = sourcekitd_response_get_value( resp )
        let map = sourcekitd_variant_dictionary_get_value( dict, sourceKit.syntaxID )
        sourcekitd_variant_array_apply( map ) { (_,dict) in
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
    
    func buildSite( for project: Project, into htmlDir: String, state: AppController ) {
        state.setChangesSource(header: "Building source site into \(htmlDir)")
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
                let path = entities[0].file

                dataByFile[path] = NSData(contentsOfFile: path) ?? NSData()
                linesByFile[path] = htmlFor(path: path, data: dataByFile[path]!, entities: entities, shortform: true)
            }

            for (usrID, _) in referencesByUSR {
                referencesByUSR[usrID]!.sort { $0.0 < $0.1 }
            }

            func htmlFile( _ path: String ) -> String {
                return state.relative( path ).replacingOccurrences(of: "/", with: "_") + ".html"
            }

            func href( _ entity: Entity ) -> String {
                return "\(htmlFile(entity.file))#L\(entity.line)"
            }

            let common = state.sourceHTML()

            let siteThreads = 4, threadPool = DispatchGroup()

            for threadNumber in 0..<siteThreads {
                threadPool.enter()
                DispatchQueue.global().async {
                    for fileNumber in stride(from: threadNumber,
                     through: entiesForFiles.count-1, by: siteThreads) {
                        let entities = entiesForFiles[fileNumber]
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

                        let final = htmlDir.url.appendingPathComponent(htmlFile(path))
                        try? out.write(to: final, atomically: false, encoding: .utf8)
                        DispatchQueue.main.async {
                            state.appendSource(title: "", text: "Wrote <a href=\"file://\(final.path)\">\(final.path)</a>\n")
                        }
                    }

                    threadPool.leave()
                }
            }

            threadPool.wait()

            let workspace = state.project?.workspaceName ?? "unknown"
            var sources = common+"</pre><div class=filelist><h2>Sources for Project \(workspace)</h2><script> document.title = 'Sources for Project \(workspace)' </script>"
            
            for entities in entiesForFiles.sorted(by: { $0.0[0].file < $0.1[0].file }) {
                let path =  entities[0].file
                sources += "<a href='\(htmlFile(path))'>\(state.relative(path))</a><br>"
            }
            
            sources += "<p>Cross Reference can be found <a href='xref.html'>here</a>."
            
            let index = htmlDir+"index.html"
            try? sources.write(toFile: index, atomically: false, encoding: .utf8)
            NSWorkspace.shared().open(index.url)
            
            sources = common+"</pre><div class=filelist><h2>Symbols defined in \(workspace)</h2><script> document.title = 'Symbols defined in \(workspace)' </script>"
            
            for entity in declarationsByUSR.values.sorted(by: {demangle($0.0.usr)! < demangle($0.1.usr)!}) {
                sources += "<a href='\(href(entity))'>\(demangle(entity.usr)!)</a><br>"
            }
            
            let xref = htmlDir+"xref.html"
            try? sources.write(toFile: xref, atomically: false, encoding: .utf8)
        }
    }

    deinit {
        for (_, resp) in maps {
            sourcekitd_request_release(resp)
        }
    }

}
