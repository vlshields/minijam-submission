#!/bin/bash -eu

EMSCRIPTEN_SDK_DIR="$HOME/emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

odin build src/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -vet -strict-style -disallow-do -out:$OUT_DIR/game.wasm.o

ODIN_PATH=$(odin root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a"

emcc -o $OUT_DIR/index.html $files \
	-sUSE_GLFW=3 \
	-sWASM_BIGINT \
	-sWARN_ON_UNDEFINED_SYMBOLS=0 \
	-sASSERTIONS \
	-sEXPORTED_RUNTIME_METHODS='["HEAPF32"]' \
	-sALLOW_MEMORY_GROWTH=1 \
	-sINITIAL_HEAP=33554432 \
	-sSTACK_SIZE=131072 \
	--js-library src/main_web/emscripten_sleep_noop.js \
	--shell-file src/main_web/index_template.html \
	--preload-file assets

rm $OUT_DIR/game.wasm.o

echo "Web build created in ${OUT_DIR}"