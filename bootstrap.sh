#!/usr/bin/env sh
# Initialize submodules for building kwatcher-afk.
#
# Do NOT use `git submodule update --init --recursive` here: fully recursive
# init materializes every kw package's nested vendor tree (~800 build.zig.zon
# manifests) and overwhelms zig's dependency-graph walk. The `.kw-workspace`
# marker makes the vendored packages resolve each other as flat siblings, so
# nested vendor copies are unnecessary — only the build-time imports and
# vendored C dependencies below must exist on disk.
#
# Shallow fetches assume every pin sits on a remote branch tip (currently
# true); run `git fetch --unshallow` inside a submodule if you need history.
set -e
git submodule update --init --jobs 8 --depth 1
git -C vendor/core     submodule update --init --depth 1 vendor/zettel
git -C vendor/protocol submodule update --init --depth 1 vendor/zettel
git -C vendor/kwev     submodule update --init --depth 1 vendor/zstd
git -C vendor/amqp     submodule update --init --depth 1 vendor/zamqp
git -C vendor/amqp/vendor/zamqp submodule update --init --depth 1 vendor/rabbitmq-c
