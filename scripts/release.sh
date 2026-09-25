#!/bin/bash
# Full Vaire release: bump version, build+sign+zip, GH release, bump cask, brew upgrade.
# Usage: scripts/release.sh [X.Y.Z] ["release notes"]
#   X.Y.Z omitted -> patch-bump current MARKETING_VERSION.
#   notes omitted  -> auto-generated from commits since the last tag.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOMEBREW_DIR="$HOME/projects/homebrew-vaire"
cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree not clean, commit or stash first" >&2
  git status --short >&2
  exit 1
fi

CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

if [[ -n "${1:-}" ]]; then
  NEW_VERSION="$1"
else
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi

if [[ -n "${2:-}" ]]; then
  NOTES="$2"
else
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [[ -n "$LAST_TAG" ]]; then
    NOTES=$(git log "${LAST_TAG}..HEAD" --pretty='format:- %s')
  else
    NOTES="Release v${NEW_VERSION}"
  fi
  if [[ -z "$NOTES" ]]; then
    NOTES="Release v${NEW_VERSION}"
  fi
fi

echo "==> Releasing v${NEW_VERSION} (was ${CURRENT_VERSION})"

sed -i '' -E "s/(MARKETING_VERSION: )\"${CURRENT_VERSION}\"/\1\"${NEW_VERSION}\"/" project.yml
sed -i '' -E "s/(CFBundleShortVersionString: )\"${CURRENT_VERSION}\"/\1\"${NEW_VERSION}\"/" project.yml

git add project.yml
git commit -m "chore: bump version to ${NEW_VERSION}"
git push

echo "==> xcodegen"
xcodegen generate

SCRATCH=$(mktemp -d)
ARCHIVE_PATH="${SCRATCH}/Vaire.xcarchive"

echo "==> xcodebuild archive"
xcodebuild -project Vaire.xcodeproj -scheme VaireApp -configuration Release \
  -archivePath "$ARCHIVE_PATH" archive

APP_DIR="${ARCHIVE_PATH}/Products/Applications"
mv "${APP_DIR}/VaireApp.app" "${APP_DIR}/Vaire.app"

rm -f "${APP_DIR}/Vaire.app/Contents/embedded.provisionprofile"
rm -f "${APP_DIR}/Vaire.app/Contents/PlugIns/VaireWidgetExtension.appex/Contents/embedded.provisionprofile"
codesign --force --deep --sign - "${APP_DIR}/Vaire.app/Contents/PlugIns/VaireWidgetExtension.appex"
codesign --force --deep --sign - "${APP_DIR}/Vaire.app"

ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}/Vaire.app" "${APP_DIR}/Vaire.zip"
SHA256=$(shasum -a 256 "${APP_DIR}/Vaire.zip" | awk '{print $1}')

echo "==> gh release"
gh release create "v${NEW_VERSION}" "${APP_DIR}/Vaire.zip" \
  --repo MartinMatousek/Vaire --title "v${NEW_VERSION}" --notes "$NOTES"

echo "==> bump cask"
cd "$HOMEBREW_DIR"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: homebrew-vaire working tree not clean" >&2
  git status --short >&2
  exit 1
fi
sed -i '' -E "s/(version )\"${CURRENT_VERSION}\"/\1\"${NEW_VERSION}\"/" Casks/vaire.rb
sed -i '' -E "s/(sha256 )\"[0-9a-f]+\"/\1\"${SHA256}\"/" Casks/vaire.rb
git add Casks/vaire.rb
git commit -m "chore: bump vaire to ${NEW_VERSION}"
git push

echo "==> brew upgrade"
brew update
brew upgrade --cask vaire || brew reinstall --cask vaire

rm -rf "$SCRATCH"
echo "==> Done: v${NEW_VERSION}"
