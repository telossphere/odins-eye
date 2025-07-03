#!/bin/bash

# Odin's Eye Platform - Simple Package Creator
# Creates a clean release package with all project files

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="odins-eye"
VERSION="1.0.0"
RELEASE_DIR="release"
PACKAGE_DIR="$RELEASE_DIR/$PACKAGE_NAME-v$VERSION"

echo -e "${BLUE}📦 Creating Odin's Eye Platform Package${NC}"
echo -e "${CYAN}Version: $VERSION${NC}"
echo

# Clean up previous release
echo -e "${BLUE}🧹 Cleaning up previous release...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$PACKAGE_DIR"
echo -e "${GREEN}✅ Cleanup complete${NC}"

# Copy all project files
echo -e "${BLUE}📋 Copying project files...${NC}"

# Copy main directories
cp -r app/ "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  app/ directory not found${NC}"
cp -r docker/ "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  docker/ directory not found${NC}"
cp -r scripts/ "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  scripts/ directory not found${NC}"

# Copy root files
cp deploy.sh "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  deploy.sh not found${NC}"
cp docker-compose.yml "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  docker-compose.yml not found${NC}"
cp README.md "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  README.md not found${NC}"
cp LICENSE "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  LICENSE not found${NC}"
cp CHANGELOG.md "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  CHANGELOG.md not found${NC}"
cp CODE_OF_CONDUCT.md "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  CODE_OF_CONDUCT.md not found${NC}"
cp CONTRIBUTING.md "$PACKAGE_DIR/" 2>/dev/null || echo -e "${YELLOW}⚠️  CONTRIBUTING.md not found${NC}"

echo -e "${GREEN}✅ Files copied${NC}"

# Set permissions
echo -e "${BLUE}🔐 Setting permissions...${NC}"
chmod +x "$PACKAGE_DIR/deploy.sh" 2>/dev/null || true
chmod +x "$PACKAGE_DIR/scripts/"*.sh 2>/dev/null || true
echo -e "${GREEN}✅ Permissions set${NC}"

# Create archives
echo -e "${BLUE}📦 Creating archives...${NC}"
cd "$RELEASE_DIR"
tar -czf "${PACKAGE_NAME}-v${VERSION}.tar.gz" "${PACKAGE_NAME}-v${VERSION}/"
zip -r "${PACKAGE_NAME}-v${VERSION}.zip" "${PACKAGE_NAME}-v${VERSION}/"
cd ..
echo -e "${GREEN}✅ Archives created${NC}"

# Show summary
echo -e "\n${GREEN}🎉 Package Creation Complete!${NC}"
echo -e "${BLUE}📦 Package Information:${NC}"
echo -e "  • Name: ${CYAN}$PACKAGE_NAME-v$VERSION${NC}"
echo -e "  • Location: ${CYAN}$PACKAGE_DIR${NC}"
echo -e "  • Size: ${CYAN}$(du -sh "$PACKAGE_DIR" | cut -f1)${NC}"
echo
echo -e "${BLUE}📦 Archives:${NC}"
ls -la "$RELEASE_DIR"/*.tar.gz "$RELEASE_DIR"/*.zip 2>/dev/null || true
echo
echo -e "${YELLOW}💡 Next Steps:${NC}"
echo -e "  1. Test the package: ${GREEN}cd $PACKAGE_DIR && ./deploy.sh${NC}"
echo -e "  2. Create GitHub release with the archives"
echo -e "  3. Share with the community"
