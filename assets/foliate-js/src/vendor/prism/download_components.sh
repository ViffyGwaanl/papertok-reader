#!/bin/bash

# Prism.js Components Downloader
# Downloads all language components from Prism.js CDN

VERSION="1.29.0"
BASE_URL="https://cdn.jsdelivr.net/npm/prismjs@${VERSION}/components"
TARGET_DIR="components"

# Create components directory if it doesn't exist
mkdir -p "$TARGET_DIR"

echo "Downloading Prism.js v${VERSION} components..."
echo "Target directory: $TARGET_DIR"
echo ""

# List of all Prism.js language components
# This includes the most commonly used languages and their dependencies
COMPONENTS=(
  # Core dependencies
  "prism-core.min.js"
  
  # Popular languages
  "prism-markup.min.js"
  "prism-css.min.js"
  "prism-clike.min.js"
  "prism-javascript.min.js"
  "prism-typescript.min.js"
  "prism-jsx.min.js"
  "prism-tsx.min.js"
  
  # System languages
  "prism-bash.min.js"
  "prism-shell-session.min.js"
  "prism-powershell.min.js"
  "prism-batch.min.js"
  
  # Web languages
  "prism-markup-templating.min.js"
  "prism-php.min.js"
  "prism-php-extras.min.js"
  "prism-json.min.js"
  "prism-yaml.min.js"
  "prism-toml.min.js"
  "prism-xml-doc.min.js"
  "prism-sass.min.js"
  "prism-scss.min.js"
  "prism-less.min.js"
  
  # C family
  "prism-c.min.js"
  "prism-cpp.min.js"
  "prism-csharp.min.js"
  "prism-objectivec.min.js"
  
  # Java family
  "prism-java.min.js"
  "prism-kotlin.min.js"
  "prism-scala.min.js"
  "prism-groovy.min.js"
  
  # Modern languages
  "prism-go.min.js"
  "prism-rust.min.js"
  "prism-swift.min.js"
  "prism-dart.min.js"
  "prism-elixir.min.js"
  "prism-erlang.min.js"
  "prism-haskell.min.js"
  "prism-julia.min.js"
  "prism-lua.min.js"
  "prism-perl.min.js"
  "prism-r.min.js"
  
  # Scripting languages
  "prism-python.min.js"
  "prism-ruby.min.js"
  
  # Database
  "prism-sql.min.js"
  "prism-plsql.min.js"
  "prism-mongodb.min.js"
  
  # Markup/Config
  "prism-markdown.min.js"
  "prism-latex.min.js"
  "prism-docker.min.js"
  "prism-git.min.js"
  "prism-diff.min.js"
  "prism-ini.min.js"
  "prism-properties.min.js"
  "prism-makefile.min.js"
  "prism-nginx.min.js"
  "prism-graphql.min.js"
  "prism-protobuf.min.js"
  
  # Other useful languages
  "prism-basic.min.js"
  "prism-vbnet.min.js"
  "prism-visual-basic.min.js"
  "prism-regex.min.js"
  "prism-http.min.js"
  "prism-dns-zone-file.min.js"
  "prism-csv.min.js"
)

# Download each component
SUCCESS=0
FAILED=0

for component in "${COMPONENTS[@]}"; do
  echo -n "Downloading $component... "
  if curl -f -s -o "$TARGET_DIR/$component" "$BASE_URL/$component"; then
    echo "✓"
    ((SUCCESS++))
  else
    echo "✗ FAILED"
    ((FAILED++))
  fi
done

echo ""
echo "=========================================="
echo "Download complete!"
echo "Success: $SUCCESS files"
echo "Failed: $FAILED files"
echo "=========================================="
echo ""
echo "Files downloaded to: $TARGET_DIR/"
echo ""
echo "Note: This script downloads commonly used languages."
echo "For a complete list, visit:"
echo "https://github.com/PrismJS/prism/tree/master/components"
