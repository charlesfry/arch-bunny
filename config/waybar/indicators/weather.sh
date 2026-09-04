#!/usr/bin/env bash
# One line of weather for the waybar `custom/weather` module. CHOICES.md
# `status-bar`.
#
# No jq, no JSON. wttr.in's `?format=` endpoint answers in plain text, so this is
# one curl and one substitution. Omarchy's version pulls `format=j1`, parses it
# with jq to pick a weather code, then maps 40 codes to Nerd Font glyphs across a
# 30-line case statement — a package we do not have, a font we do not ship
# (`font` picked Fragment Mono, which has no icon glyphs), and a lot of code to
# show less than the temperature does.
#
# curl needs no ledger row: pacman itself depends on it.
#
# Location is not in this repo. wttr.in geolocates by IP when given nothing, which
# is the right default for a stranger who cloned this. The author's own
# coordinates are a personal detail, so they live in one machine-local file next
# to the dirmap.conf already there. Note what handing them over costs: the IP
# default tells wttr.in roughly which city you are in, the file tells it your
# street.
#
#   printf '<lat>,<lon>\n' > ~/.config/bunny/weather-location
#
# Failure is visible: no network, no wttr.in, a bad location, and the bar says
# `weather n/a` rather than going blank. There is deliberately no cache — a stale
# reading shown as current is worse than no reading.
#
# Usage: weather [--help]
set -Eeuo pipefail

case "${1-}" in
-h | --help)
	sed -n '2,/^set -/p' "$0" | sed 's|^# \?||;$d'
	exit
	;;
esac

loc_file=${XDG_CONFIG_HOME:-$HOME/.config}/bunny/weather-location
loc=
if [[ -r $loc_file ]]; then
	read -r loc <"$loc_file" || true
fi

# `%t` is the temperature in whatever unit wttr.in infers for the location, `%C`
# the condition in words. `-f` turns an HTTP error into a non-zero exit instead of
# a body full of HTML.
#
# The retry is a loop and not `curl --retry`, and that distinction is the whole
# bug. niri spawns waybar ~9 s into boot; NetworkManager writes /etc/resolv.conf
# at ~12 s. The first poll therefore runs before the machine can resolve anything,
# and because `interval` is also the retry interval the bar then read
# `weather n/a` for fifteen minutes on a machine whose network was fine.
#
# `curl --retry 5 --retry-all-errors` was the obvious fix and did not work:
# instrumented across a real boot, six attempts over fifteen seconds all returned
# `curl: (6) Could not resolve host`, including attempts thirteen seconds after
# the default route came up. glibc reads /etc/resolv.conf once per process, so a
# curl started before NetworkManager wrote it has no nameserver for its entire
# life. On the boot that proved it: resolv.conf written 14:15:59.725, first curl
# started 14:15:58.198.
#
# So each attempt must be a new process. Six of them, five seconds apart, which
# covers the ~12 s the network takes and costs about 25 s on a machine that is
# genuinely offline — in a background process nothing is waiting on.
out=
for attempt in 1 2 3 4 5 6; do
	if ((attempt > 1)); then sleep 5; fi
	if out=$(curl -fsS --max-time 5 "https://wttr.in/${loc}?format=%t+%C" 2>/dev/null); then
		break
	fi
	out=
done

if [[ -z $out ]]; then
	printf 'weather n/a\n'
	exit 0
fi

# wttr.in answers 200 with prose for an unparseable location, so the shape of the
# reply is checked rather than the exit status alone.
if [[ ! $out =~ ^[[:space:]]*[+-]?[0-9]+° ]]; then
	printf 'weather n/a\n'
	exit 0
fi

# `+77°F` reads as an instruction rather than a temperature, and wttr.in pads its
# reply with a trailing space the stylesheet's own padding then doubles.
out=${out#"${out%%[![:space:]]*}"}
out=${out%"${out##*[![:space:]]}"}
printf '%s\n' "${out#+}"
