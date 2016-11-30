//
//  Project.swift
//  Refactorator
//
//  Created by John Holdsworth on 20/11/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Cocoa

let HOME = String( cString: getenv("HOME") )

extension Entity {

    var sourceName: String {
        return file.url.lastPathComponent
    }

}

class Project {

    static let sourceKit = SourceKit()
    static var lastProject: Project?
    static var unknown = "unknown"

    let xCode: SBApplication?
    var workspaceDoc: SBObject?

    var workspacePath = unknown
    var projectRoot = unknown
    var derivedData = unknown
    var indexPath = unknown
    var indexDB: IndexDB?

    var entity: Entity?

    var maps = [String:sourcekitd_response_t]()

    var workspaceName: String {
        return workspacePath.url.lastPathComponent
    }

    static func openWorkspace( workspaceDoc: SBObject?, workspacePath: String, relative: Bool ) throws -> (String, String, String, IndexDB?) {
        let workspaceURL = workspacePath.url
        let projectRoot = workspaceURL.deletingLastPathComponent().path
        let projectName = workspaceURL.deletingPathExtension().lastPathComponent
        let derivedData = (relative ? projectRoot.url.appendingPathComponent("DerivedData") :
            HOME.url.appendingPathComponent("Library/Developer/Xcode/DerivedData")).appendingPathComponent( projectName
                .replacingOccurrences(of: " ", with: "_") + (relative ? "" : "-" + Utils.hashString(forPath: workspacePath)) ).path

        let deployments  = try FileManager.default.contentsOfDirectory(atPath: derivedData+"/Index/Debug")
        let runDest = workspaceDoc?.activeRunDestination
        func makeIndexPath( _ platformArch: String ) -> String {
            return "\(derivedData)/Index/Debug/\(platformArch)/\(projectName).xcindex/db.xcindexdb"
        }

        let platformArch = deployments.filter { $0 != ".DS_Store" &&
            (runDest == nil || ($0.hasPrefix(runDest!.platform) && $0.hasSuffix(runDest!.architecture))) }.sorted(by: {
            (a, b) in
            return mtime( makeIndexPath( a )+".strings-res" ) > mtime( makeIndexPath( b )+".strings-res" )
        } ).first

//        if platformArch == nil {
//            throw NSError(domain: "Could not find an index db", code: 0, userInfo: ["DerivedData":derivedData])
//        }

        let indexPath = platformArch != nil ? makeIndexPath( platformArch! ) : "notfound"
        return (projectRoot, derivedData, indexPath, IndexDB(dbPath: indexPath))
    }

    static func findProject(for target: Entity) -> String? {
        let manager = FileManager.default

        func fileWithExtension( ext: String, in dirURL: URL ) -> String? {
            do {
                for name in try manager.contentsOfDirectory(atPath: dirURL.path) {
                    if name.url.pathExtension == ext {
                        return name
                    }
                }
            }
            catch {
                xcode.error("Could not list directory \(dirURL)")
            }
            return nil
        }

        for ext in ["xcworkspace", "xcodeproj"] {
            var potentialRoot = target.file.url.deletingLastPathComponent()
            while potentialRoot.path != "/" {
                if let foundProject = fileWithExtension(ext: ext, in: potentialRoot) {
                    return potentialRoot.appendingPathComponent(foundProject).path
                }
                potentialRoot.deleteLastPathComponent()
            }
        }

        return nil
    }

    init(target: Entity?) {
        xCode = SBApplication(bundleIdentifier:"com.apple.dt.Xcode")
        IndexDB.projectDirs.removeAll()

        if let xCode = xCode {
            var workspaceDocs = [String:SBObject]()
            for workspace in xCode.workspaceDocuments().map( { $0 as! SBObject } ) {
                workspaceDocs[workspace.path] = workspace
            }

            let windows = xCode.windows().sorted(by: {
                return ($0 as! SBObject).index < ($1 as! SBObject).index
            }).filter { ($0 as! SBObject).document.path != nil }

            for window in windows {
                workspacePath = (window as! SBObject).document!.path
                workspaceDoc = workspaceDocs[workspacePath]
                do {
                    (projectRoot, derivedData, indexPath, indexDB) =
                        try Project.openWorkspace(workspaceDoc: workspaceDoc, workspacePath: workspacePath, relative: true)
                    if target != nil ? IndexDB.projectIncludes(file: target!.file) : true {
                        break
                    }
                }
                catch {
                    do {
                        (projectRoot, derivedData, indexPath, indexDB) =
                            try Project.openWorkspace(workspaceDoc: workspaceDoc, workspacePath: workspacePath, relative: false)
                        if target != nil ? IndexDB.projectIncludes(file: target!.file) : true {
                            break
                        }
                    }
                    catch (let e) {
                        xcode.log("Could not find indexDB for any open workspace docs \(e)")
                    }
                }
            }

            let relevantDoc = xCode.sourceDocuments().filter {
                let sourceDoc = $0 as! SBObject
                return IndexDB.projectIncludes(file: sourceDoc.path) && sourceDoc.selectedCharacterRange != nil
            }.last

            if let sourceDoc = relevantDoc as? SBObject {
                let sourcePath = sourceDoc.path.url.resolvingSymlinksInPath().path

                do {
                    let sourceString = try NSString( contentsOfFile: sourcePath, encoding: String.Encoding.utf8.rawValue )
                    let range = sourceDoc.selectedCharacterRange
                    let sourceOffset = range == nil ? nil :
                        sourceString.substring(with: NSMakeRange(0, range![0].intValue-1)).utf8.count

                    entity = Entity( file: sourcePath, offset: sourceOffset )
                }
                catch (let e) {
                    xcode.error( "Could not load source \(sourcePath) - \(e)" )
                }
            }
        }

        if target != nil && !IndexDB.projectIncludes(file: target!.file),
            let alternate = Project.findProject(for: target!) {
            workspacePath = alternate
            workspaceDoc = nil
            do {
                (projectRoot, derivedData, indexPath, indexDB) =
                    try Project.openWorkspace(workspaceDoc: workspaceDoc, workspacePath: workspacePath, relative: true)
            }
            catch {
                do {
                    (projectRoot, derivedData, indexPath, indexDB) =
                        try Project.openWorkspace(workspaceDoc: workspaceDoc, workspacePath: workspacePath, relative: false)
                }
                catch {
                    xcode.error("Error finding indexDB for \(workspacePath)")
                }
            }
        }

        if indexDB == nil && Project.lastProject?.indexDB != nil {
            let project = Project.lastProject!
            (workspacePath, projectRoot, derivedData, indexPath, indexDB) =
                (project.workspacePath, project.projectRoot, project.derivedData, project.indexPath, IndexDB(dbPath: project.indexPath))
        }
        Project.lastProject = self

//        else if entity == nil {
//            xcode.error( "No appropriate source file open in Xcode under project: \(workspacePath)" )
//        }

//        if indexDB == nil {
////            xcode.error("Could not open an indexDB for \(workspacePath)")
//            return nil
//        }
    }

    deinit {
        for (_, resp) in maps {
            sourcekitd_request_release(resp)
        }
    }

}
