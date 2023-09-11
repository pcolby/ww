#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2023 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: GPL-3.0-or-later

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

: "${CACHE_DIR:=.}"

function showUsage {
  echo "$(cat <<--
	Usage: ${BASH_SOURCE[0]} <run_url> > mermaid.txt
	   or: ${BASH_SOURCE[0]} <owner> <repo> <run_id> [<attempt_number>] > mermaid.txt
	-
	)"
}

# Parse the CLI's postional arguments.
if [[ $# -eq 1 ]]; then
  read -r owner repo runId attemptNumber < <(
    sed -Ene 's|.*/([^/]*)/([^/]*)/actions/runs/([0-9]+)(/attempts/([0-9]+))?$|\1 \2 \3 \5|p' <<< "$1"
  ) || { echo "Invalid workflow run URL: $1" >&2; showUsage; exit 2; }
  [[ -n "$attemptNumber" ]] || unset attemptNumber
elif [[ $# -ge 3 && $# -le 4 ]]; then
  username=$1; repo=$2; runId=$3
  [[ $# -lt 4 ]] || attemptNumber=$4
else
  showUsage; exit 1
fi

# Fetch the run details.
runApiPath="/repos/$owner/$repo/actions/runs/$runId${attemptNumber:+/attempts/$attemptNumber}"
echo "Fetching $runApiPath" >&2
runDetails=$(gh api "$runApiPath")

# Fetch the run jobs. Note, we don't use $runDetails.jobs_url here, because it always lacks the
# attempt number. I'd call this a bug in GitHub's REST API.
jobsApiPath="/repos/$owner/$repo/actions/runs/$runId${attemptNumber:+/attempts/$attemptNumber}/jobs"
echo "Fetching $jobsApiPath" >&2
runJobs=$(gh api "$jobsApiPath")

# Generate Mermaid Gantt chart header.
jq -er "$(cat <<-"-"
	"---\ndisplayMode: compact\n---\ngantt\n" +
	"  title " + ([.name,(.id|tostring),.run_attempt|tostring]|join(" #")) + "\n" +
	"  dateFormat YYYY-MM-DDTHH:MM:SS.SSSZ\n  %% "+ .html_url
	-
	)" <<< "$runDetails"

# Generate Mermaid Gantt chart sections.
jq -er "$(cat <<-"-"
	def isodate(d): d|strptime("%FT%T.000%z")|mktime;
        def isodiff(d1;d2): isodate(d2)-isodate(d1);
	.jobs[]|"\n  section " + .name + "\n" + (
	  [.steps[]|"  " + .name + " : " + .started_at + ", " + (isodiff(.started_at;.completed_at)|tostring) + "s"]|
	  join("\n")
	)
	-
	)" <<< "$runJobs"
