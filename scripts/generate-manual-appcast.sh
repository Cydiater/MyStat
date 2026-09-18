#!/usr/bin/env bash
# Advertise a manual GitHub download without enabling automatic installation.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 2 ]] || { echo "Usage: $0 RELEASE.zip RELEASE_NOTES.md" >&2; exit 1; }
archive="$1"
notes="$2"
[[ -f "$archive" && -f "$notes" ]] || { echo "Release archive or notes missing." >&2; exit 1; }
sparkle_tools=".build/artifacts/sparkle/Sparkle/bin"
account="${MYSTAT_SPARKLE_ACCOUNT:-com.cydiater.MyStat.sparkle}"
[[ -x "$sparkle_tools/sign_update" ]] || swift package resolve
stage=$(mktemp -d "${TMPDIR:-/tmp}/mystat-manual-appcast.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$archive" "$stage/unpacked"
app="$stage/unpacked/MyStat.app"
plist="$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
[[ "$("$sparkle_tools/generate_keys" --account "$account" -p)" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" ]] || {
    echo "Signing key does not match the released app." >&2; exit 1;
}
"$sparkle_tools/sign_update" --account "$account" --verify docs/appcast.xml
python3 - "$plist" "$notes" "$stage/appcast.xml" <<'PY'
import datetime, email.utils, plistlib, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path
plist_path, notes_path, output = sys.argv[1:]
plist = plistlib.loads(Path(plist_path).read_bytes())
version, build = plist['CFBundleShortVersionString'], plist['CFBundleVersion']
if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
    raise SystemExit('Expected a three-part version and integer build number.')
if plist.get('SUFeedURL') != 'https://cydiater.github.io/MyStat/appcast.xml' or plist.get('SURequireSignedFeed') is not True:
    raise SystemExit('Release must use the signed production feed.')
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
tree = ET.parse('docs/appcast.xml')
channel = tree.find('channel')
if channel is None:
    raise SystemExit('Missing appcast channel.')
for previous in channel.findall('item'):
    previous_build = previous.findtext(f'{{{ns}}}version')
    if previous_build is None:
        enclosure = previous.find('enclosure')
        previous_build = enclosure.get(f'{{{ns}}}version') if enclosure is not None else None
    if previous_build is None or int(previous_build) >= int(build):
        raise SystemExit('Manual releases must have a newer build than existing entries.')
item = ET.Element('item')
ET.SubElement(item, 'title').text = f'MyStat {version} — GitHub download'
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = plist['LSMinimumSystemVersion']
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, 'link').text = f'https://github.com/Cydiater/MyStat/releases/tag/v{version}'
ET.SubElement(item, 'description', {'format': 'markdown'}).text = (
    'Choose **Learn More…** to open GitHub and download this release. Quit MyStat before replacing the app in Applications.\n\n'
    + Path(notes_path).read_text())
# No enclosure: Sparkle presents Learn More, never downloads or installs this item.
channel.insert(0, item)
ET.indent(tree, space='  ')
tree.write(output, encoding='utf-8', xml_declaration=True)
PY
"$sparkle_tools/sign_update" --account "$account" "$stage/appcast.xml"
"$sparkle_tools/sign_update" --account "$account" --verify "$stage/appcast.xml"
cp "$stage/appcast.xml" docs/appcast.xml
echo "Prepared a signed GitHub download notice. Verify the release assets, then publish docs/appcast.xml."
