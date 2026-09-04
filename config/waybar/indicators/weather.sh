#!/usr/bin/env bash

# Usage: weather [--help]
#
# Shows the current temperature/condition, same as before. When rain or
# snow is expected later today it's appended, e.g. "68°F Cloudy | Rain
# 60% 3pm-6pm"; otherwise nothing extra is shown. If the risky stretch
# is already underway and its condition matches what's currently
# reported, the two are merged instead, e.g. "68°F Moderate rain 86%
# until 9pm".
set -Eeuo pipefail

# chance-of-rain/snow (%) at/above which an hour gets flagged
threshold=30

case "${1-}" in
-h | --help)
	sed -n '2,/^set -/p' "$0" | sed 's|^# \?||;$d'
	exit
	;;
esac

# printf '<lat>,<lon>\n' > ~/.config/bunny/weather-location

loc_file=${XDG_CONFIG_HOME:-$HOME/.config}/bunny/weather-location
loc=
if [[ -r $loc_file ]]; then
	read -r loc <"$loc_file" || true
fi

current=
for attempt in 1 2 3 4 5 6; do
	if ((attempt > 1)); then sleep 5; fi
	if current=$(curl -fsS --max-time 5 "https://wttr.in/${loc}?format=%t+%C" 2>/dev/null); then
		break
	fi
	current=
done

if [[ -z $current ]] || [[ ! $current =~ ^[[:space:]]*[+-]?[0-9]+° ]]; then
	printf '{"text":"weather n/a"}\n'
	exit 0
fi

# `+77°F` reads as an instruction rather than a temperature, and wttr.in pads its
# reply with a trailing space the stylesheet's own padding then doubles.
current=${current#"${current%%[![:space:]]*}"}
current=${current%"${current##*[![:space:]]}"}
current=${current#+}

# The condition text alone (temp stripped), used to detect whether the
# currently-reported condition is the same one the forecast is warning about.
current_desc=$(sed -E 's/^-?[0-9]+°[A-Za-z]+[[:space:]]*//' <<<"$current")

# Best-effort forecast check: a single attempt, and we fall back to the
# current-conditions text alone if it fails.
json=$(curl -fsS --max-time 5 "https://wttr.in/${loc}?format=j1" 2>/dev/null) || json=

if [[ -z $json ]]; then
	printf '{"text":"%s"}\n' "$current"
	exit 0
fi

jq -c --arg current "$current" --arg current_desc "$current_desc" --argjson now "$(date +%-H)" --argjson threshold "$threshold" '
  def to12h: (. % 24) as $h
    | if $h == 0 then "12am"
      elif $h < 12 then "\($h)am"
      elif $h == 12 then "12pm"
      else "\($h - 12)pm"
      end;
  def clean: gsub("^\\s+|\\s+$"; "");

  .weather[0].hourly
  | map(. + {risk: ([(.chanceofrain // "0" | tonumber), (.chanceofsnow // "0" | tonumber)] | max)})
  | map(select((.time | tonumber / 100 | floor) + 3 > $now))
  | map(select(.risk >= $threshold)) as $hits
  | if ($hits | length) == 0 then
      {text: $current}
    else
      ($hits | max_by(.risk)) as $peak
      | ($hits[0].time | tonumber / 100 | floor) as $start
      | (($hits[-1].time | tonumber / 100 | floor) + 3) as $end
      | (($now >= $start) and ($now < $end)
         and (($peak.weatherDesc[0].value | clean | ascii_downcase) == ($current_desc | clean | ascii_downcase))) as $ongoing_match
      | {
          text: (if $ongoing_match then
                   "\($current) \($peak.risk)% until \($end|to12h)"
                 else
                   "\($current) | \($peak.weatherDesc[0].value | clean) \($peak.risk)% \($start|to12h)-\($end|to12h)"
                 end),
          tooltip: ($hits | map("\(.time | tonumber / 100 | floor | to12h)  \(.weatherDesc[0].value | clean)  \(.risk)%") | join("\n"))
        }
    end
' <<<"$json" || printf '{"text":"%s"}\n' "$current"
