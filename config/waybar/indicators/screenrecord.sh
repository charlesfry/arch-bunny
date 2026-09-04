#!/bin/bash

if pidof gpu-screen-recorder >/dev/null; then
  echo '{"text": "󰑊", "tooltip": "Stop screenrecording", "class": "active"}'
else
  echo '{"text": ""}'
fi
