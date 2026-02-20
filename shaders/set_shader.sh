#!/bin/bash

cleanup() {
    local SHADER_DIR="$1"
    local ACTIVE_NAME="$2"
    # Delete all OTHER active files
    find "$SHADER_DIR" -maxdepth 1 -type f -name ".reshadeck.active.*.fx" ! -name "$ACTIVE_NAME" -delete
}

FXNAME="$1"
SHADER_DIR="$2"
FORCE="${3:-true}"

if [ "$FXNAME" = "None" ] || [ -z "$FXNAME" ]; then
    DISPLAY=:0 xprop -root -remove GAMESCOPE_RESHADE_EFFECT
    exit 0
fi

if [ ! -f "$SHADER_DIR/$FXNAME" ]; then
    echo "Shader file $FXNAME not found in $SHADER_DIR"
    DISPLAY=:0 xprop -root -remove GAMESCOPE_RESHADE_EFFECT
    exit 1
fi

# Check current state if FORCE is false
if [ "$FORCE" = "false" ]; then
    CURRENT_VAL=$(DISPLAY=:0 xprop -root GAMESCOPE_RESHADE_EFFECT | cut -d '=' -f 2 | tr -d ' "')
    
    # Check if current value matches our pattern (.reshadeck.active.*.fx)
    if [[ "$CURRENT_VAL" == .reshadeck.active.*.fx ]]; then
        CURRENT_FILE="$SHADER_DIR/$CURRENT_VAL"
        if [ -f "$CURRENT_FILE" ]; then
            # Just overwrite the existing active file
            echo "Updating existing active shader $CURRENT_VAL"
            if cp "$SHADER_DIR/$FXNAME" "$CURRENT_FILE"; then
                exit 0
            else
                echo "Failed to update active file, falling back to full apply"
            fi
        fi
    fi
fi

# Generate new random active filename
RAND=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)
ACTIVE_NAME=".reshadeck.active.${RAND}.fx"
FULL_ACTIVE="$SHADER_DIR/$ACTIVE_NAME"
XPROP_VAL="$ACTIVE_NAME"

# Copy staging file to new active file
if ! cp "$SHADER_DIR/$FXNAME" "$FULL_ACTIVE"; then
    echo "Failed to create active shader file"
    cleanup "$SHADER_DIR" "$ACTIVE_NAME"
    exit 1
fi

# Apply to Gamescope
if ! DISPLAY=:0 xprop -root -f GAMESCOPE_RESHADE_EFFECT 8u -set GAMESCOPE_RESHADE_EFFECT "$XPROP_VAL"; then
    echo "Failed to set xprop"
    cleanup "$SHADER_DIR" "$ACTIVE_NAME"
    rm "$FULL_ACTIVE"
    exit 1
fi

exit 0
