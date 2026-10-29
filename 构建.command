#!/bin/zsh
set -eu
cd "${0:A:h}"
# 公开入口默认构建独立配置的清洁版；旧版界面不再参与构建。
VTNEXT_UNIVERSAL=1 ./Next/build.command "${1:-clean}"
