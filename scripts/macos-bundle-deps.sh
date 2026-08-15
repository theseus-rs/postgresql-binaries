#!/usr/bin/env bash

set -e

INSTALL_DIR="$1"
BREW_PREFIX="$2"

if [ -z "$INSTALL_DIR" ] || [ -z "$BREW_PREFIX" ]; then
    echo "Usage: $0 <install_dir> <brew_prefix>"
    exit 1
fi

echo "Bundling dependencies for $INSTALL_DIR"
echo "Brew prefix: $BREW_PREFIX"

mkdir -p "$INSTALL_DIR/lib"

# Function to get real path
get_realpath() {
    python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1"
}

sign_mach_o_files() {
    echo "Signing Mach-O files"
    find "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" -type f -print0 | while IFS= read -r -d '' file_path; do
        if file "$file_path" | grep -q "Mach-O"; then
            echo "  Signing: ${file_path#$INSTALL_DIR/}"
            chmod +w "$file_path"
            codesign --force --sign - "$file_path"
        fi
    done
}

# Function to bundle a library and its dependencies
bundle_lib() {
    local lib_path="$1"
    local lib_name="${2:-}"
    if [ -z "$lib_name" ]; then
        lib_name=$(basename "$lib_path")
    fi
    
    if [ -f "$INSTALL_DIR/lib/$lib_name" ]; then
        return
    fi
    
    echo "  Bundling $lib_name"
    cp "$lib_path" "$INSTALL_DIR/lib/$lib_name"
    chmod +w "$INSTALL_DIR/lib/$lib_name"
    
    # Set the ID of the dylib to be relative
    install_name_tool -id "@loader_path/../lib/$lib_name" "$INSTALL_DIR/lib/$lib_name"
    
    # Get Homebrew and same-directory dependencies and fix them
    otool -L "$INSTALL_DIR/lib/$lib_name" | awk 'NR > 1 {print $1}' | while read -r dep; do
        local dep_path
        case "$dep" in
            "$BREW_PREFIX"/*)
                dep_path="$dep"
                ;;
            @loader_path/*|@rpath/*)
                dep_path="$(dirname "$lib_path")/${dep#*/}"
                if [ ! -e "$dep_path" ]; then
                    continue
                fi
                ;;
            *)
                continue
                ;;
        esac

        local dep_name=$(basename "$dep")
        if [ "$dep_name" = "$lib_name" ]; then
            continue
        fi

        local dep_real_path=$(get_realpath "$dep_path")
        bundle_lib "$dep_real_path" "$dep_name"
        echo "    Changing dependency $dep to @loader_path/../lib/$dep_name in $lib_name"
        install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$INSTALL_DIR/lib/$lib_name"
    done
}

# Fix binaries in bin/
echo "Processing binaries in $INSTALL_DIR/bin"
find "$INSTALL_DIR/bin" -type f | while read -r binary; do
    if file "$binary" | grep -q "Mach-O"; then
        echo "  Processing binary: $(basename "$binary")"
        otool -L "$binary" | grep "$BREW_PREFIX" | awk '{print $1}' | while read -r dep; do
            dep_real_path=$(get_realpath "$dep")
            dep_name=$(basename "$dep")
            bundle_lib "$dep_real_path" "$dep_name"
            echo "    Changing dependency $dep to @loader_path/../lib/$dep_name"
            install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$binary"
        done
        
        # Also fix internal PG libs if they are absolute
        otool -L "$binary" | grep "$INSTALL_DIR" | awk '{print $1}' | while read -r dep; do
            dep_name=$(basename "$dep")
            echo "    Changing internal dependency to @loader_path/../lib/$dep_name"
            install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$binary"
        done
    fi
done

# Finally, ensure all dylibs in lib/ have correct IDs and internal references
echo "Processing libraries in $INSTALL_DIR/lib"
find "$INSTALL_DIR/lib" -maxdepth 1 -name "*.dylib" | while read -r lib; do
    if [ ! -L "$lib" ] && file "$lib" | grep -q "Mach-O"; then
        echo "  Processing library: $(basename "$lib")"
        chmod +w "$lib"
        install_name_tool -id "@loader_path/../lib/$(basename "$lib")" "$lib"
        
        # Fix dependencies to other Homebrew libs
        otool -L "$lib" | grep "$BREW_PREFIX" | awk '{print $1}' | while read -r dep; do
            dep_real_path=$(get_realpath "$dep")
            dep_name=$(basename "$dep")
            bundle_lib "$dep_real_path" "$dep_name"
            install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$lib"
        done

        # Fix internal PG references
        otool -L "$lib" | grep "$INSTALL_DIR" | awk '{print $1}' | while read -r dep; do
            dep_name=$(basename "$dep")
            install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$lib"
        done
    fi
done

sign_mach_o_files

echo "Done bundling dependencies."
