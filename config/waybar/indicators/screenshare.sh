#!/bin/bash

streams=$(pw-cli list-objects 2>/dev/null | grep -c "Stream/Output/Video")
recording=$(pidof gpu-screen-recorder >/dev/null && echo 1 || echo 0)

if [[ $((streams - recording)) -gt 0 ]]; then
  echo '{"text": "󰐯", "tooltip": "Screen sharing active", "class": "active"}'
else
  echo '{"text": ""}'
fi
