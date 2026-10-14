#!/bin/bash

if makoctl mode | grep -q '^dnd$'; then
  echo '{"text": "󰜺", "tooltip": "Notifications Disabled", "class": "active"}'
else
  echo '{"text": "󰂚", "tooltip": "Notifications Enabled"}'
fi
