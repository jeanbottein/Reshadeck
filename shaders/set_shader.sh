#!/bin/bash

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

REL_DIR=$(dirname "$FXNAME")
FILENAME=$(basename "$FXNAME")

# Generate new random active filename
RAND=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)
ACTIVE_NAME=".reshadeck.active.${RAND}.fx"

if [ "$REL_DIR" = "." ]; then
    FULL_ACTIVE="$SHADER_DIR/$ACTIVE_NAME"
    XPROP_VAL="$ACTIVE_NAME"
else
    FULL_ACTIVE="$SHADER_DIR/$REL_DIR/$ACTIVE_NAME"
    XPROP_VAL="$REL_DIR/$ACTIVE_NAME"
fi

# Copy staging file to new active file
if ! cp "$SHADER_DIR/$FXNAME" "$FULL_ACTIVE"; then
    echo "Failed to create active shader file"
    exit 1
fi

# Apply to Gamescope
if ! DISPLAY=:0 xprop -root -f GAMESCOPE_RESHADE_EFFECT 8u -set GAMESCOPE_RESHADE_EFFECT "$XPROP_VAL"; then
    echo "Failed to set xprop"
    rm "$FULL_ACTIVE"
    exit 1
fi

# Delete all OTHER active files (garbage collection) except the current one
find "$SHADER_DIR" -type f -name ".reshadeck.active.*.fx" ! -path "$FULL_ACTIVE" -delete

exit 0

