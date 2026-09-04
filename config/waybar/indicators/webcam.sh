#!/bin/bash

if lsof /dev/video* 2>/dev/null | grep -q .; then
  echo '{"text": "", "tooltip": "Webcam active", "class": "active"}'
else
  echo '{"text": ""}'
fi
