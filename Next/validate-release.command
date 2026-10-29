#!/bin/zsh
set -eu
cd "${0:A:h}/.."
./Next/test.command
./Next/test-workspace.command
./Next/test-audio.command
./Next/test-export.command
VTNEXT_UNIVERSAL=1 ./Next/build.command personal
VTNEXT_UNIVERSAL=1 ./Next/build.command clean
