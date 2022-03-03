#!/bin/sh

export XDG_RUNTIME_DIR=/run/user/`id -u ${WESTON_USER}`
v4l2-ctl --set-parm=30
v4l2-ctl --set-fmt-video=width=320,height=240,pixelformat=RGBP
gst-launch-1.0 v4l2src ! "video/x-raw, width=320, height=240, framerate=(fraction)15/1" ! queue ! waylandsink
