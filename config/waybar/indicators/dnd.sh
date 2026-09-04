#!/bin/bash

if makoctl mode | grep -q '^dnd$'; then
  echo '{"text": "󰜺", "tooltip": "Disable dnd", "class": "active"}'
else
  echo '{"text": ""}'
fi
