/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getcwd
import func POSIX.getenv
import func POSIX.chdir
import func libc.exit
import ManifestParser
import PackageType
import Multitool
import Transmute
import Xcodeproj
import Utility
import Build
import Get


private let origwd = (try? getcwd()) ?? "/"

extension String {
    private var prettied: String {
        if self.parentDirectory == origwd {
            return "./\(basename)"
        } else if hasPrefix(origwd) {
            return Path(self).relative(to: origwd)
        } else {
            return self
        }
    }
}


do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    verbosity = Verbosity(rawValue: opts.verbosity)

    if let dir = opts.chdir {
        try chdir(dir)
    }
    
    func parseManifest(path path: String, baseURL: String) throws -> Manifest {
        let bindir = try! Process.arguments.first!.parentDirectory.abspath()
        let libdir: String
        if Path.join(bindir, "PackageDescription.swiftmodule").isDirectory { //FIXME HACK
            libdir = bindir
        } else {
            libdir = try! Path.join(bindir, "../lib/swift/pm").abspath()
        }
        return try Manifest(path: path, baseURL: baseURL, swiftc: Toolchain.swiftc, libdir: libdir)
    }
    
    func fetch(root: String) throws -> (rootPackage: Package, externalPackages:[Package]) {
        let manifest = try parseManifest(path: root, baseURL: root)
        return try get(manifest, manifestParser: parseManifest)
    }

    switch mode {
        case .Build(let conf):
            let dirs = try directories()
            let (rootPackage, externalPackages) = try fetch(dirs.root)
            let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
            let yaml = try describe(dirs.build, conf, modules, products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc)
            try build(YAMLPath: yaml, target: "default")

        case .Init(let initMode):
            let initPackage = try InitPackage(mode: initMode)
            try initPackage.writePackageStructure()
                        
        case .Fetch:
            try fetch(try directories().root)

        case .Usage:
            usage()

        case .Clean(.Dist):
            try rmtree(try directories().root, "Packages")
            fallthrough
        case .Clean(.Build):
            try rmtree(try directories().root, ".build")

        case .Version:
            print("Apple Swift Package Manager 0.1")
            
        case .GenerateXcodeproj(let outpath):
            let dirs = try directories()
            let (rootPackage, externalPackages) = try fetch(dirs.root)
            let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
            
            let swiftModules = modules.flatMap{ $0 as? SwiftModule }
            let externalSwiftModules = externalModules.flatMap{ $0 as? SwiftModule }

            let projectName: String
            let dstdir: String
            let packageName = rootPackage.name

            switch outpath {
            case let outpath? where outpath.hasSuffix(".xcodeproj"):
                // if user specified path ending with .xcodeproj, use that
                projectName = String(outpath.basename.characters.dropLast(10))
                dstdir = outpath.parentDirectory
            case let outpath?:
                dstdir = outpath
                projectName = packageName
            case _:
                dstdir = dirs.root
                projectName = packageName
            }

            let outpath = try Xcodeproj.generate(dstdir: dstdir, projectName: projectName, srcroot: dirs.root, modules: swiftModules, externalModules: externalSwiftModules, products: products)

            print("generated:", outpath.prettied)
    }

} catch {
    handleError(error, usage: usage)
}
