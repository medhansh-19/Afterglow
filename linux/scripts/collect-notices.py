"""Collect the license texts shipped with the pinned Rust dependencies for binary bundles."""
from pathlib import Path
import json,subprocess,shutil,urllib.request
root=Path(__file__).resolve().parents[1]
output=root/'src-tauri'/'notices';output.mkdir(exist_ok=True)
rustc=shutil.which('rustc') or str(Path.home()/'.cargo/bin/rustc')
cargo=shutil.which('cargo') or str(Path.home()/'.cargo/bin/cargo')
triple=subprocess.check_output([rustc,'-vV'],text=True,encoding='utf-8').split('host: ')[1].splitlines()[0]
metadata=json.loads(subprocess.check_output([cargo,'metadata','--manifest-path',str(root/'src-tauri'/'Cargo.toml'),'--locked','--format-version','1','--filter-platform',triple],text=True,encoding='utf-8'))
rows=[]
for package in metadata['packages']:
    if not package['source']:continue
    folder=Path(package['manifest_path']).parent;name=f"{package['name']}-{package['version']}"
    destination=output/name;destination.mkdir(exist_ok=True)
    files=[]
    for source in folder.iterdir():
        if source.is_file() and source.name.upper().startswith(('LICENSE','LICENCE','COPYING','NOTICE','COPYRIGHT')):
            shutil.copyfile(source,destination/source.name);files.append(source.name)
    rows.append(f"{name}: {package.get('license') or 'see package license'}; {', '.join(files) or package.get('license_file') or 'license text supplied by upstream package'}")
(output/'Rust-dependencies.txt').write_text('\n'.join(sorted(rows))+'\n',encoding='utf-8')
for name,url in {
 'Swift-LICENSE.txt':'https://raw.githubusercontent.com/swiftlang/swift/swift-6.2.1-RELEASE/LICENSE.txt',
 'Swift-Foundation-LICENSE.txt':'https://raw.githubusercontent.com/swiftlang/swift-corelibs-foundation/swift-6.2.1-RELEASE/LICENSE',
 'ICU-LICENSE.txt':'https://raw.githubusercontent.com/unicode-org/icu/release-76-1/LICENSE',
}.items():
    target=output/name
    if not target.exists():
        with urllib.request.urlopen(url,timeout=30) as response:target.write_bytes(response.read())
shutil.copyfile(root.parent/'LICENSE',output/'Afterglow-LICENSE.txt')
shutil.copyfile(root.parent/'THIRD_PARTY_NOTICES.md',output/'Mac-and-shared-dependencies.md')
print(f'Collected notices for {len(rows)} Rust dependencies plus the shared Swift runtime.')
