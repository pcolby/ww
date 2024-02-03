#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2023-2024 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: GPL-3.0-or-later

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

: "${CURRENT_SOURCE_DIR:=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" || :)")}"
: "${PROJECT_SOURCE_DIR:=$(dirname "${CURRENT_SOURCE_DIR}")}"
: "${TEST_DATA_DIR:=${CURRENT_SOURCE_DIR}/data}"

echo 'Running tests...'
while IFS= read -d '' -r fileName; do
  testName=$(basename "${fileName}" .json)
  echo "Test: ${testName}"
  IFS=- read -r owner repo runId attemptNumber <<< "${testName}"
  export TEST_RUN_FILE="${fileName}" TEST_JOBS_FILE="${fileName%.json}-jobs.json"
  "${PROJECT_SOURCE_DIR}/ww.sh" "${owner}" "${repo}" "${runId}" "${attemptNumber}" >| "${fileName%.json}.out"
  diff --color=auto --unified "${fileName%.json}".{txt,out}
done < <(find "${TEST_DATA_DIR}" -name '*.json' -not -name '*-jobs.json' -print0 || :)
echo 'All tests passed.'
