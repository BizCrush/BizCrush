#!/bin/bash
set -e

# BizCrush macOS Desktop Release Script
# This script builds the macOS app locally and deploys to BizCrush/BizCrush GitHub Pages

echo "🚀 BizCrush macOS Release Builder"
echo "=================================="

# Configuration
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_DIR/app"
DEPLOY_REPO="https://github.com/BizCrush/BizCrush.git"
DEPLOY_BRANCH="gh-pages"
SPARKLE_PRIVATE_KEY_FILE="$HOME/.bizcrush/sparkle_private_key.pem"

# Check if version is provided
if [ -z "$1" ]; then
  echo "❌ Error: Version required"
  echo "Usage: ./release-macos.sh <version>"
  echo "Example: ./release-macos.sh 0.21.0"
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"

echo "📦 Version: $VERSION"
echo "🏷️  Tag: $TAG"
echo ""

# Step 1: Check prerequisites
echo "🔍 Checking prerequisites..."

if [ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]; then
  echo "❌ Error: Sparkle private key not found at $SPARKLE_PRIVATE_KEY_FILE"
  echo ""
  echo "Please create the file with your Sparkle private key:"
  echo "  mkdir -p ~/.bizcrush"
  echo "  echo 'YOUR_PRIVATE_KEY_HERE' > $SPARKLE_PRIVATE_KEY_FILE"
  echo "  chmod 600 $SPARKLE_PRIVATE_KEY_FILE"
  exit 1
fi

# Check for fvm or flutter
if command -v fvm &> /dev/null; then
  FLUTTER_CMD="fvm flutter"
  echo "✅ Using fvm flutter"
elif command -v flutter &> /dev/null; then
  FLUTTER_CMD="flutter"
  echo "✅ Using flutter directly"
else
  echo "❌ Error: Neither fvm nor flutter found. Please install Flutter."
  exit 1
fi

if ! command -v create-dmg &> /dev/null; then
  echo "📦 Installing create-dmg..."
  brew install create-dmg
fi

echo "✅ Prerequisites OK"
echo ""

# Step 2: Build the app
echo "🔨 Building macOS app..."
cd "$APP_DIR"

# Clean previous builds
$FLUTTER_CMD clean

# Get dependencies
$FLUTTER_CMD pub get

# Build for release
$FLUTTER_CMD build macos --release --target=lib/main_desktop.dart

APP_PATH="$APP_DIR/build/macos/Build/Products/Release/BizCrush.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Error: BizCrush.app not found at $APP_PATH"
  exit 1
fi

echo "✅ Build completed: $APP_PATH"
echo ""

# Step 3: Create DMG
echo "📦 Creating DMG installer..."
mkdir -p "$APP_DIR/dist/updates"
DMG_PATH="$APP_DIR/dist/updates/BizCrush-${TAG}.dmg"

# Remove existing DMG if present
rm -f "$DMG_PATH"

create-dmg \
  --volname "BizCrush" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  --hide-extension "BizCrush.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH" || {
    echo "⚠️  create-dmg failed, trying hdiutil fallback..."
    hdiutil create -volname "BizCrush" \
      -srcfolder "$APP_PATH" \
      -ov -format UDZO \
      "$DMG_PATH"
  }

if [ ! -f "$DMG_PATH" ]; then
  echo "❌ Error: DMG creation failed"
  exit 1
fi

echo "✅ DMG created: $DMG_PATH"
DMG_SIZE=$(stat -f%z "$DMG_PATH")
echo "   Size: $(numfmt --to=iec-i --suffix=B $DMG_SIZE 2>/dev/null || echo ${DMG_SIZE})"
echo ""

# Step 4: Sign DMG with Sparkle
echo "🔐 Signing DMG for Sparkle updates..."

SIGNATURE=$(openssl dgst -sha256 -sign "$SPARKLE_PRIVATE_KEY_FILE" \
  -out /tmp/signature.bin \
  "$DMG_PATH" && \
  openssl base64 -in /tmp/signature.bin -A)

rm -f /tmp/signature.bin

echo "✅ Signature: $SIGNATURE"
echo ""

# Step 5: Generate appcast.xml
echo "📝 Generating appcast.xml..."

APPCAST_PATH="$APP_DIR/dist/updates/appcast.xml"
DMG_URL="https://bizcrush.github.io/BizCrush/BizCrush-${TAG}.dmg"
PUB_DATE=$(date -R)

# Check if critical update
if [[ "$TAG" == *"critical"* ]]; then
  CRITICAL="true"
else
  CRITICAL="false"
fi

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BizCrush Updates</title>
    <description>Most recent updates to BizCrush</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <description>
        <![CDATA[
          <h2>What's New in ${VERSION}</h2>
          <ul>
            <li>Check the release notes for details</li>
          </ul>
        ]]>
      </description>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
      <sparkle:criticalUpdate>${CRITICAL}</sparkle:criticalUpdate>
      <enclosure
        url="${DMG_URL}"
        sparkle:edSignature="${SIGNATURE}"
        length="${DMG_SIZE}"
        type="application/octet-stream"
        sparkle:os="macos" />
    </item>
  </channel>
</rss>
EOF

echo "✅ appcast.xml generated"
echo ""

# Step 6: Clone/update deployment repository
echo "📤 Preparing deployment repository..."

DEPLOY_DIR="/tmp/bizcrush-deploy-$$"
rm -rf "$DEPLOY_DIR"

git clone --depth 1 --branch "$DEPLOY_BRANCH" "$DEPLOY_REPO" "$DEPLOY_DIR" || {
  echo "📝 Creating new deployment repository..."
  git clone --depth 1 "$DEPLOY_REPO" "$DEPLOY_DIR"
  cd "$DEPLOY_DIR"
  git checkout --orphan "$DEPLOY_BRANCH"
  git rm -rf . || true
}

cd "$DEPLOY_DIR"

# Step 7: Copy files to deployment repository
echo "📋 Copying files..."

cp "$DMG_PATH" .
cp "$APPCAST_PATH" .

# Copy download page if exists
DOWNLOAD_PAGE="$REPO_DIR/desktop/download-page/index.html"
if [ -f "$DOWNLOAD_PAGE" ]; then
  cp "$DOWNLOAD_PAGE" .
  echo "✅ Copied download page"
fi

echo ""
echo "📊 Files to deploy:"
ls -lh BizCrush-*.dmg appcast.xml index.html 2>/dev/null || ls -lh BizCrush-*.dmg appcast.xml
echo ""

# Step 8: Commit and push
echo "🚀 Deploying to GitHub Pages..."

git add .
git commit -m "Deploy BizCrush macOS ${TAG}

- Version: ${VERSION}
- DMG: BizCrush-${TAG}.dmg
- Size: ${DMG_SIZE} bytes
- Date: ${PUB_DATE}
" || {
  echo "⚠️  No changes to commit"
}

git push origin "$DEPLOY_BRANCH"

echo "✅ Deployed to GitHub Pages!"
echo ""

# Step 9: Create GitHub tag and release
echo "🏷️  Creating GitHub tag and release..."

cd "$REPO_DIR"

# Check if tag exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "⚠️  Tag $TAG already exists. Delete it? (y/n)"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    git tag -d "$TAG"
    git push --delete origin "$TAG" || true
  else
    echo "❌ Aborted"
    exit 1
  fi
fi

# Create and push tag
git tag -a "$TAG" -m "Release ${VERSION}"
git push origin "$TAG"

echo "✅ Tag $TAG created and pushed"
echo ""

# Step 10: Create GitHub Release (using gh CLI if available)
if command -v gh &> /dev/null; then
  echo "📝 Creating GitHub Release..."

  gh release create "$TAG" "$DMG_PATH" \
    --title "BizCrush ${TAG}" \
    --notes "## BizCrush ${TAG}

### Installation
1. Download the DMG file below
2. Open the DMG and drag BizCrush to Applications
3. Launch BizCrush

### Auto-Update
This version supports automatic updates. The app will check for updates every hour.

### Downloads
- macOS: \`BizCrush-${TAG}.dmg\`

### Links
- Download page: https://bizcrush.github.io/BizCrush/
- Update feed: https://bizcrush.github.io/BizCrush/appcast.xml
"

  echo "✅ GitHub Release created!"
else
  echo "⚠️  gh CLI not found. Please create GitHub Release manually:"
  echo "   https://github.com/adelab-inc/biz-crush/releases/new"
  echo "   Tag: $TAG"
  echo "   Upload: $DMG_PATH"
fi

# Cleanup
rm -rf "$DEPLOY_DIR"

echo ""
echo "✅ Release completed successfully!"
echo ""
echo "📋 Summary:"
echo "   Version: ${VERSION}"
echo "   Tag: ${TAG}"
echo "   DMG: BizCrush-${TAG}.dmg"
echo "   Size: ${DMG_SIZE} bytes"
echo ""
echo "🌐 URLs:"
echo "   Download page: https://bizcrush.github.io/BizCrush/"
echo "   DMG download: ${DMG_URL}"
echo "   Update feed: https://bizcrush.github.io/BizCrush/appcast.xml"
echo ""
echo "🎉 Users can now download and install BizCrush ${VERSION}!"
