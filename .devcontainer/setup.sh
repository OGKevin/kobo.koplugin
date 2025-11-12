#!/bin/bash
set -e

# Version configuration
STYLUA_VERSION="2.3.1"
MDBOOK_VERSION="0.4.52"
MDBOOK_MERMAID_VERSION="0.16.2"

echo "Setting up development environment for kobo.koplugin..."

# Update package list
sudo apt-get update

# Install Lua 5.2
echo "Installing Lua 5.2..."
sudo apt-get install -y lua5.2 liblua5.2-dev

# Install LuaRocks
echo "Installing LuaRocks..."
sudo apt-get install -y luarocks

# Install Lua tools via LuaRocks
echo "Installing Lua development tools..."
sudo luarocks install busted
sudo luarocks install luacov
sudo luarocks install luacheck

# Install StyLua
echo "Installing StyLua..."
wget -q "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-x86_64.zip" -O /tmp/stylua.zip
sudo unzip -q /tmp/stylua.zip -d /usr/local/bin/
sudo chmod +x /usr/local/bin/stylua
rm /tmp/stylua.zip

# Install Prettier (via npm which comes with Node feature)
echo "Installing Prettier..."
npm install -g prettier

# Install act for local GitHub Actions testing
echo "Installing act..."
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Install mdBook for documentation
echo "Installing mdBook..."
wget -q "https://github.com/rust-lang/mdBook/releases/download/v${MDBOOK_VERSION}/mdbook-v${MDBOOK_VERSION}-x86_64-unknown-linux-gnu.tar.gz" -O /tmp/mdbook.tar.gz
sudo tar -xzf /tmp/mdbook.tar.gz -C /usr/local/bin/
rm /tmp/mdbook.tar.gz

# Install mdbook-mermaid for diagrams
echo "Installing mdbook-mermaid..."
wget -q "https://github.com/badboy/mdbook-mermaid/releases/download/v${MDBOOK_MERMAID_VERSION}/mdbook-mermaid-v${MDBOOK_MERMAID_VERSION}-x86_64-unknown-linux-gnu.tar.gz" -O /tmp/mdbook-mermaid.tar.gz
sudo tar -xzf /tmp/mdbook-mermaid.tar.gz -C /usr/local/bin/
rm /tmp/mdbook-mermaid.tar.gz

# Initialize mdbook-mermaid
echo "Initializing mdbook-mermaid..."
mdbook-mermaid install

# Verify installations
echo ""
echo "Verifying installations..."
echo "Lua version: $(lua -v)"
echo "LuaRocks version: $(luarocks --version | head -n1)"
echo "Busted: $(busted --version)"
echo "Luacheck: $(luacheck --version)"
echo "StyLua: $(stylua --version)"
echo "Prettier: $(prettier --version)"
echo "Act: $(act --version)"
echo "mdBook: $(mdbook --version)"
echo "mdbook-mermaid: $(mdbook-mermaid --version)"

echo ""
echo "Development environment setup complete!"
echo "You can now run:"
echo "  - busted spec/           # Run tests"
echo "  - stylua --check .       # Check Lua formatting"
echo "  - luacheck .             # Lint Lua code"
echo "  - prettier --check .     # Check markdown/JSON formatting"
echo "  - act -j test            # Test GitHub Actions locally"
echo "  - mdbook serve           # Serve documentation locally"
