import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const source = readFileSync(new URL('../../SoundiscoApp/Features/Authentication/ViewModels/PasswordRecoveryViewModel.swift', import.meta.url), 'utf8');
const start = source.indexOf('nonisolated final class TemporaryAuthStorage:');
const end = source.indexOf('\n@MainActor', start);
if (start < 0 || end < 0) throw new Error('TemporaryAuthStorage declaration not found');
const directory = mkdtempSync(join(tmpdir(), 'soundisco-auth-storage-'));
const swift = `import Foundation
protocol AuthLocalStorage: Sendable {
    func store(key: String, value: Data) throws
    func retrieve(key: String) throws -> Data?
    func remove(key: String) throws
}
${source.slice(start, end)}

let recovery = TemporaryAuthStorage()
let reauthentication = TemporaryAuthStorage()
let token = Data("test-session".utf8)
try recovery.store(key: "session", value: token)
precondition(try recovery.retrieve(key: "session") == token)
precondition(try reauthentication.retrieve(key: "session") == nil)
let refreshed = Data("refreshed-session".utf8)
try recovery.store(key: "session", value: refreshed)
precondition(try recovery.retrieve(key: "session") == refreshed)
try recovery.store(key: "verifier", value: token)
try recovery.remove(key: "session")
precondition(try recovery.retrieve(key: "session") == nil)
precondition(try recovery.retrieve(key: "verifier") == token)
DispatchQueue.concurrentPerform(iterations: 100) { index in
    let key = "key-\\(index)"
    try! recovery.store(key: key, value: token)
    precondition(try! recovery.retrieve(key: key) == token)
    try! recovery.remove(key: key)
}
print("PASS session retention, refresh, client isolation, removal and concurrent access")
`;
writeFileSync(join(directory, 'main.swift'), swift.replaceAll('precondition(try ', 'precondition(try! '));
execFileSync('xcrun', ['swiftc', join(directory, 'main.swift'), '-o', join(directory, 'test')], { stdio: 'inherit' });
execFileSync(join(directory, 'test'), [], { stdio: 'inherit' });
