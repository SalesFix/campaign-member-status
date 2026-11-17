#!/bin/sh
# Rebuilds doc-assets/highlight.js from pinned versions so the published docs site
# never picks up an unreviewed release. Bump these deliberately and review the diff.
HLJS_VERSION="11.9.0"
HLJS_APEX_VERSION="1.5.0"

set -e
curl --fail --silent --show-error -L "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@${HLJS_VERSION}/build/highlight.min.js" -o "doc-assets/highlight.js"
echo >> "doc-assets/highlight.js"
curl --fail --silent --show-error -L "https://cdn.jsdelivr.net/npm/highlightjs-apex@${HLJS_APEX_VERSION}/dist/apex.min.js" >> "doc-assets/highlight.js"

echo "doc-assets/highlight.js rebuilt (highlight.js ${HLJS_VERSION}, highlightjs-apex ${HLJS_APEX_VERSION})"
sha256sum "doc-assets/highlight.js" 2>/dev/null || shasum -a 256 "doc-assets/highlight.js"
