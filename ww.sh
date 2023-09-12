#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2023 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: GPL-3.0-or-later

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

: "${DISPLAY_MODE:=compact}"
: "${MIN_STEP_DURATION:=1}"

function showUsage {
  cat <<--
	Usage: ${BASH_SOURCE[0]} <run_url> > mermaid.txt
	   or: ${BASH_SOURCE[0]} <owner> <repo> <run_id> [<attempt_number>] > mermaid.txt
	-
}

# Parse the CLI's postional arguments.
if [[ $# -eq 1 ]]; then
  read -r owner repo runId attemptNumber < <(
    sed -Ene 's|.*/([^/]*)/([^/]*)/actions/runs/([0-9]+)(/attempts/([0-9]+))?$|\1 \2 \3 \5|p' <<< "$1"
  ) || { echo "Invalid workflow run URL: $1" >&2; showUsage; exit 2; }
  [[ -n "$attemptNumber" ]] || unset attemptNumber
elif [[ $# -ge 3 && $# -le 4 ]]; then
  owner=$1; repo=$2; runId=$3
  [[ $# -lt 4 ]] || attemptNumber=$4
else
  showUsage; exit 1
fi

readonly API_PATH="/repos/$owner/$repo/actions/runs/$runId${attemptNumber:+/attempts/$attemptNumber}"

# Generate Mermaid Gantt chart header.
jq -er --arg displayMode "$DISPLAY_MODE" "$(cat <<-"-"
        def safe(s): s|gsub("[;#]";""); # Note, `:` is ok in titles.
	"---\ndisplayMode: " + $displayMode + "\n---\ngantt\n" +
	"  title " + safe(.name) + " (run " + (.id|tostring) + ", attempt " + (.run_attempt|tostring) + ")\n" +
	"  dateFormat YYYY-MM-DDTHH:MM:SS.SSSZ\n  %% "+ .html_url
	-
	)" < <(gh api "$API_PATH")

# Generate Mermaid Gantt chart sections.
jq -er --argjson minStepDuration "$MIN_STEP_DURATION" "$(cat <<-"-"
	def isodate(d): d|strptime("%FT%T.000%z")|mktime;
        def isodiff(d1;d2): isodate(d2)-isodate(d1);
        def safe(s): s|gsub("[:;#]";"");
	.jobs[]|"\n  section " + safe(.name) + "\n" + ([
	  .steps[]|select(.completed_at)|
	  (.+{duration:isodiff(.started_at;.completed_at)})|
	  select(.duration>=$minStepDuration or .conclusion=="failed")|
	  "  " + safe(.name) + " :" +
	  if .conclusion != "success" then "crit, " else "" end +
	  .started_at + ", " + (.duration|tostring) + "s"
	]|join("\n"))
	-
	)" < <(gh api "$API_PATH/jobs" --paginate)
