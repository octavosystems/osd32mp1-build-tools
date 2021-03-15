#!/bin/sh

export XDG_RUNTIME_DIR=/run/user/`id -u ${WESTON_USER}`
gst-play-1.0 OSD32MP1_RED_intro_360p.mp4

