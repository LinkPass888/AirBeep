#!/usr/bin/env python3
"""Run the production Foundation-only Tendies import logic on regression fixtures.

Usage: python3 scripts/test-tendies-import.py [path/to/package.tendies]
Reference: Nugget 26e0c50ec114ca3a4ff6ab2fb4ae309abfd39fa1,
src/tweaks/posterboard/posterboard_tweak.py, recursive_add:
Container preserves paths/content; standalone descriptors randomize identifiers.
"""
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
source = (ROOT / 'airbeep/Airlift/TendiesEngine.swift').read_text()


def section(start, end):
    return source[source.index(start):source.index(end)].replace('private func', 'func')


update = section('    private func updatePlistIdentifiers', '    // MARK: - Folder Injector Helper')
find = source[source.index('    private func findDescriptorsWithExtensions'):source.rfind('\n}')].replace('private func', 'func')
# Execute the actual preparation block used immediately before Airlift injection.
prepare = section('                let targetUUID = descItem.preservesIdentifiers', '                for sVer in versionsToWrite')

with tempfile.TemporaryDirectory(prefix='airbeep-tendies-test-') as tmp:
    tmp = pathlib.Path(tmp)
    fixtures = tmp / 'fixtures'
    store = 'Library/Application Support/PRBPosterExtensionDataStore/61/Extensions'
    uuid = 'C127E8D0-67E8-4B32-9154-F6E47F2DDD0B'
    for layout in ['wrapped', 'unwrapped', 'standalone']:
        base = fixtures / layout
        for ext in ['com.apple.MercuryPoster', 'com.apple.WallpaperKit.CollectionsPoster']:
            package = base / ext
            if layout == 'wrapped':
                descriptor = package / 'iPhone 18 Pro' / 'Container' / store / ext / 'descriptors' / uuid
            elif layout == 'unwrapped':
                descriptor = package / 'container' / store / ext / 'descriptors' / uuid
            else:
                descriptor = package / 'descriptors' / uuid
            contents = descriptor / 'versions/0/contents'
            contents.mkdir(parents=True)
            (descriptor / 'com.apple.posterkit.provider.descriptor.identifier').write_text('v6x.colorA')
            (contents / 'com.apple.posterkit.provider.contents.userInfo').write_bytes(plistlib.dumps({'lookIdentifier': 'colorA'}))
            (contents / 'Wallpaper.plist').write_bytes(plistlib.dumps({'identifier': 'original', 'keep': 'value'}))
            (contents / '.com.apple.posterkit.provider.contents.configurableOptions.plist').write_bytes(b'hidden content')
    real = tmp / 'real'
    if len(sys.argv) > 1:
        with zipfile.ZipFile(sys.argv[1]) as archive:
            # The fixture is local, but never extract paths outside the temporary directory.
            for name in archive.namelist():
                path = pathlib.PurePosixPath(name)
                if path.is_absolute() or '..' in path.parts:
                    raise ValueError('Unsafe archive path')
            archive.extractall(real)

    swift = 'import Foundation\n' + update + find + '''
let fm = FileManager.default
func log(_ message: String) {}
func snapshot(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for case let file as URL in fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])! {
        if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[file.path] = try Data(contentsOf: file)
        }
    }
    return result
}
func verify(_ root: URL, ext: String, preserve: Bool, count: Int) throws {
    let before = try snapshot(root)
    let descriptors = findDescriptorsWithExtensions(in: root, defaultExt: ext)
    precondition(descriptors.count == count)
    precondition(Set(descriptors.map { $0.url.path }).count == count)
    for (descIndex, descItem) in descriptors.enumerated() {
        precondition(descItem.ext == ext)
        precondition(descItem.preservesIdentifiers == preserve)
''' + prepare + '''
        precondition((targetUUID == descItem.url.lastPathComponent) == preserve)
        let idURL = descItem.url.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        let identifier = try String(contentsOf: idURL, encoding: .utf8)
        if !preserve {
            precondition(Int(identifier) != nil)
            let contents = descItem.url.appendingPathComponent("versions/0/contents")
            for (name, key) in [("com.apple.posterkit.provider.contents.userInfo", "wallpaperRepresentingIdentifier"), ("Wallpaper.plist", "identifier")] {
                let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: contents.appendingPathComponent(name)), format: nil) as! [String: Any]
                precondition(plist[key] as? Int == Int(identifier))
            }
        }
    }
    let after = try snapshot(root)
    if preserve { precondition(before == after) }
    print("PASS", root.lastPathComponent, preserve ? "preserved" : "randomized", count)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
for layout in ["wrapped", "unwrapped", "standalone"] {
    for ext in ["com.apple.MercuryPoster", "com.apple.WallpaperKit.CollectionsPoster"] {
        try verify(root.appendingPathComponent("fixtures/" + layout + "/" + ext), ext: ext, preserve: layout != "standalone", count: 1)
    }
}
let real = root.appendingPathComponent("real")
if fm.fileExists(atPath: real.path) {
    try verify(real, ext: "com.apple.MercuryPoster", preserve: true, count: 4)
}
'''
    script = tmp / 'test.swift'
    script.write_text(swift)
    subprocess.run(['swift', str(script), str(tmp)], check=True)
