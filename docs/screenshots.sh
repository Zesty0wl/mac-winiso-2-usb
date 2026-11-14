#!/bin/zsh
# Rebuild the README's screenshots and walkthrough video: builds a Debug copy of the app and runs it in screenshot
# mode (sample data; no ISO or USB drive is read or written).
#   docs/screenshots/{light,dark}/   one PNG per wizard step
#   docs/walkthrough.{mp4,gif}       the whole wizard, start to finish (needs ffmpeg: brew install ffmpeg)
# For real window shots (rounded corners, shadow) the terminal needs the Screen Recording permission; without it the
# app draws its window into the image itself.
set -euo pipefail
cd "${0:A:h}/.."
build="${TMPDIR:-/tmp}/winiso2usb-screenshots"
xcodebuild -project WINISO2USB/WINISO2USB.xcodeproj -scheme WINISO2USB -configuration Debug -derivedDataPath "$build" build -quiet
app="$build/Build/Products/Debug/WINISO2USB.app/Contents/MacOS/WINISO2USB"
for look in light dark; do
  "$app" -screenshots "$PWD/docs/screenshots/$look" -appearance "$look" -ApplePersistenceIgnoreState YES
done

if command -v ffmpeg >/dev/null; then
  frames="$build/frames"
  rm -rf "$frames"
  "$app" -screenshots "$frames" -appearance light -walkthrough YES -ApplePersistenceIgnoreState YES
  # The shots are transparent around the window's shadow: put them on white. Half size (they're 2x), even dimensions.
  flat="color=white[c];[c][0:v]scale2ref[bg][fg];[bg][fg]overlay=shortest=1,scale=912:-2:flags=lanczos"
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$frames/frames.txt" -filter_complex "$flat,fps=30,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart docs/walkthrough.mp4
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$frames/frames.txt" -filter_complex "$flat,fps=10,split[x][y];[x]palettegen=max_colors=128[p];[y][p]paletteuse=dither=bayer:bayer_scale=5" docs/walkthrough.gif
  ls -lh docs/walkthrough.mp4 docs/walkthrough.gif
else
  echo "ffmpeg not found: skipped the walkthrough video"
fi
