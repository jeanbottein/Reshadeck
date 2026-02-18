#!/bin/bash

FXNAME="$1"
SHADER_DIR="$2"
FORCE="${3:-true}"

if [ "$FXNAME" = "None" ] || [ -z "$FXNAME" ]; then
    DISPLAY=:0 xprop -root -remove GAMESCOPE_RESHADE_EFFECT

else
    # Generic temp-file trick for ALL shaders to force gamescope reload
    if [ ! -f "$SHADER_DIR/$FXNAME" ]; then
        echo "Shader file $FXNAME not found in $SHADER_DIR"
        DISPLAY=:0 xprop -root -remove GAMESCOPE_RESHADE_EFFECT
        exit 1
    fi

    REL_DIR=$(dirname "$FXNAME")
    FILENAME=$(basename "$FXNAME")
    BASENAME="${FILENAME%.fx}"
    RAND=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)
    TEMPFX_NAME="${BASENAME}_${RAND}.fx"

    if [ "$REL_DIR" = "." ]; then
        FULL_TEMPFX="$SHADER_DIR/$TEMPFX_NAME"
        XPROP_VAL="$TEMPFX_NAME"
        SEARCH_DIR="$SHADER_DIR"
    else
        FULL_TEMPFX="$SHADER_DIR/$REL_DIR/$TEMPFX_NAME"
        XPROP_VAL="$REL_DIR/$TEMPFX_NAME"
        SEARCH_DIR="$SHADER_DIR/$REL_DIR"
    fi

    if [ "$FORCE" = "false" ]; then
        CURRENTFX=$(DISPLAY=:0 xprop -root GAMESCOPE_RESHADE_EFFECT 2>/dev/null \
            | awk -F'"' '/GAMESCOPE_RESHADE_EFFECT/ {print $2}')
        # Extract base name (strip _XXXXXX suffix) from current effect
        CURRENT_BASE=$(echo "$CURRENTFX" | sed -E 's/_[A-Za-z0-9]{6}\.fx$/.fx/')
        [ "$CURRENT_BASE" = "$FXNAME" ] && exit 0
    fi

    cp "$SHADER_DIR/$FXNAME" "$FULL_TEMPFX"
    DISPLAY=:0 xprop -root -f GAMESCOPE_RESHADE_EFFECT 8u -set GAMESCOPE_RESHADE_EFFECT "$XPROP_VAL"

    # Clean up old temp files for this shader (keep only the one we just created)
    # Regex matches the BASENAME followed by random suffix
    find "$SEARCH_DIR" -maxdepth 1 -type f -regextype posix-extended \
        -regex ".*/${BASENAME}_[A-Za-z0-9]{6}\.fx" ! -name "$TEMPFX_NAME" -exec rm {} \;
fi
