#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2023-2024 Paul Colby <git@colby.id.au>
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

# Parse the CLI's positional arguments.
if [[ $# -eq 1 ]]; then
  read -r owner repo runId attemptNumber < <(
    sed -Ene 's|.*/([^/]*)/([^/]*)/actions/runs/([0-9]+)(/attempts/([0-9]+))?$|\1 \2 \3 \5|p' <<< "$1" || :
  ) || { echo "Invalid workflow run URL: $1" >&2; showUsage; exit 2; }
  [[ -n "${attemptNumber}" ]] || unset attemptNumber
elif [[ $# -ge 3 && $# -le 4 ]]; then
  owner=$1; repo=$2; runId=$3
  [[ $# -lt 4 ]] || attemptNumber=$4
else
  showUsage; exit 1
fi

readonly API_PATH="/repos/${owner}/${repo}/actions/runs/${runId}${attemptNumber:+/attempts/${attemptNumber}}"

# Fetch the workflow run data.
[[ -v TEST_RUN_FILE ]] && workflowRun=$(cat "${TEST_RUN_FILE}") || workflowRun=$(gh api "${API_PATH}")
#jq . <<< "$workflowRun" >| "./test/data/$owner-$repo-$runId${attemptNumber:+-${attemptNumber}}.json"

# Generate Mermaid Gantt chart header.
jq -er --arg displayMode "${DISPLAY_MODE}" --arg unsafeChars "${PRE_MERMAID_10_8:+;#}" "$(cat <<-"-" || :
	def safeTitle(s): if ($unsafeChars|length) > 0 then s|gsub("["+$unsafeChars+"]";"") else s end;
	"---\ndisplayMode: " + $displayMode + "\n---\ngantt\n" +
	"  title " + safeTitle(.name) + " (run " + (.id|tostring) + ", attempt " + (.run_attempt|tostring) + ")\n" +
	"  dateFormat YYYY-MM-DDTHH:MM:SS.SSSZ\n  %% "+ .html_url
	-
	)" <<< "${workflowRun}"

# Fetch the worflow run jobs data.
[[ -v TEST_JOBS_FILE ]] && workflowRunJobs=$(cat "${TEST_JOBS_FILE}") || workflowRunJobs=$(gh api "${API_PATH}/jobs" --paginate)
#jq . <<< "$workflowRunJobs" >| "./test/data/$owner-$repo-$runId${attemptNumber:+-${attemptNumber}}-jobs.json"

# Add some summary metadata.
jq -er "$(cat <<-"-" || :
	def roundto(n): (n|exp10)*.|round/(n|exp10);
	def duration:
	  if   .>86400 then ./86400|roundto(1)|tostring+" days"
	  elif .>36000 then ./3600|round|tostring+" hrs"
	  elif .>7200  then ./3600|roundto(1)|tostring+" hrs"
	  elif .>600   then ./60|round|tostring+" mins"
	  elif .>120   then ./60|roundto(1)|tostring+" mins"
	  else              .|roundto(1)|tostring+" secs"
	end;
	def format: .|duration + if .>120 then " ("+(.|tostring)+" secs)" else "" end;
	def isodiff(d1;d2): (d2|fromdate)-(d1|fromdate);
	{
	  elapsed: isodiff([.jobs[].started_at]|min;[.jobs[].started_at]|max),
	  total: [.jobs[]|isodiff(.started_at;.completed_at)]|add
	}
	|"  %% duration: "+(.elapsed|format)+" elapsed, "+(.total|format)+" total."
	-
	)" <<< "${workflowRunJobs}"

# Generate Mermaid Gantt chart sections.
jq -er --argjson minStepDuration "${MIN_STEP_DURATION}" --arg unsafeChars "${PRE_MERMAID_10_8:+;#}" "$(cat <<-"-" || :
	def isodate(d): d|strptime("%FT%T.000%z")|mktime;
	def isodiff(d1;d2): isodate(d2)-isodate(d1);
	def safeSectionName(s): if ($unsafeChars|length) > 0 then s|gsub("[:"+$unsafeChars+"]";"") else s end;
	def safeTaskName(s): s|gsub("[:"+$unsafeChars+"]";"");
	.jobs[]|"\n  section " + safeSectionName(.name) + "\n" + ([
	  .steps[]|select(.completed_at)|
	  (.+{duration:isodiff(.started_at;.completed_at)})|
	  select(.duration>=$minStepDuration or .conclusion=="failed")|
	  "  " + safeTaskName(.name) + " :" +
	  if .conclusion != "success" then "crit, " else "" end +
	  .started_at + ", " + (.duration|tostring) + "s"
	]|join("\n"))
	-
	)" <<< "${workflowRunJobs}"
