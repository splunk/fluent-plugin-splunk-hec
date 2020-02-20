#!/usr/bin/env bash

# trigger SCK 'master' branch to introduce this new image from this commit 
# to working version of every other component.
ORGANIZATION=splunk
PROJECT=splunk-connect-for-kubernetes
BRANCH=$1

# Trigger functional test
curl -X POST --header "Content-Type: application/json" \
    -d '{"build_parameters": {"CIRCLE_JOB":"build_test", "TRIG_BRANCH":"'"$CIRCLE_BRANCH"'", "TRIG_PROJECT":"'"$CIRCLE_PROJECT_REPONAME"'", "TRIG_REPO":"'"$CIRCLE_REPOSITORY_URL"'"}}' "https://circleci.com/api/v1/project/$ORGANIZATION/$PROJECT/tree/$BRANCH?circle-token=$CIRCLE_TOKEN" > build.json
cat build.json
BUILD_NUM=$(jq -r .build_num build.json)

# Wait until finish or maximum 20 minutes
TIMEOUT=20
DONE="FALSE"
until [ "$TIMEOUT" -lt 0 ] || [ "$DONE" == "TRUE" ]; do
    curl https://circleci.com/api/v1/project/$ORGANIZATION/$PROJECT/$BUILD_NUM?circle-token=$CIRCLE_TOKEN > build_progress.json
    STATUS=$(jq -r .status build_progress.json)
    echo "STATUS = $STATUS"
    if [ "$STATUS" != "running" ] && [ "$STATUS" != "queued" ]; then
        DONE="TRUE"
    else
        let TIMEOUT--
        sleep 60
    fi
done

BUILD_URL=$(jq -r .build_url build_progress.json)
if [ "$DONE" == "FALSE" ]; then
    # Cancel hanging job and fail
    curl -X POST https://circleci.com/api/v1/project/$ORGANIZATION/$PROJECT/$BUILD_NUM/cancel?circle-token=$CIRCLE_TOKEN
else
    if [ "$STATUS" != "success" ] && [ "$STATUS" != "fixed" ]; then
        echo "Functional test have failed please see:"
        echo $BUILD_URL
        exit 1
    fi
    exit 0
fi
