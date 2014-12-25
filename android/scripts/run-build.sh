#!/usr/bin/env bash

set -e
set -o pipefail

cwd=$(pwd)

region="us-east-1"
region_ami="ami-c0412ea8"
sleep=10
instance_name="android-gl-build-$TRAVIS_REPO_SLUG-$TRAVIS_JOB_NUMBER"
echo $ami_name

NAME=$TRAVIS_REPO_SLUG/$TRAVIS_JOB_NUMBER

user_data="#!/bin/bash
    cd /android
    git clone git://github.com/mapbox/mapbox-gl-native.git

    pushd mapbox-gl-native
    git checkout `git rev-parse HEAD`
    git submodule update --init --recursive

    export ANDROID_NDK_PATH=/android/android-ndk-r10c
    export JAVA_HOME=/android/jdk1.7.0_71
    export ANDROID_HOME=/android/android-sdk-linux
    export PATH=\$PATH:/android/jdk1.7.0_71/bin
    export ANDROID_KEY=$ANDROID_KEY

    if ./android/scripts/build-$CONFIG.sh $NAME &>../build.log; then
        echo 'ANDROID BUILD PASSED'
    else
        echo 'ANDROID BUILD FAILED'
    fi
    popd

    aws s3 cp --region us-east-1 build.log s3://android-gl-build/${NAME}/build-log.txt
    shutdown -P now"

id=$(aws ec2 run-instances \
    --region $region \
    --image-id $region_ami \
    --count 1 \
    --instance-type m3.large \
    --iam-instance-profile Name="android-gl-build" \
    --instance-initiated-shutdown-behavior terminate \
    --user-data "$user_data" | jq -r '.Instances[0].InstanceId')

echo "Instance: $region $id"

result=$(aws ec2 create-tags --region $region --resources $id --tags "Key=Name,Value=$instance_name")

instance_status_terminated=$(aws ec2 describe-instances --region $region --instance-id $id | jq -r '.Reservations[0].Instances[0].State.Name')

until [ "$instance_status_terminated" = "terminated" ]; do
    instance_status_terminated=$(aws ec2 describe-instances --region $region --instance-id $id | jq -r '.Reservations[0].Instances[0].State.Name')
    echo "Instance terminating status $region $id: $instance_status_terminated"
    sleep $sleep
done

echo "Build finished"

output=$(aws ec2 get-console-output --region $region --instance-id $id | jq -r '.Output')

aws s3 cp --region $region s3://android-gl-build/${NAME}/build-log.txt build.log
cat build.log

if [[ $output == *"ANDROID BUILD PASSED"* ]]; then
    echo "ANDROID BUILD PASSED"
    exit 0
else
    echo "ANDROID BUILD FAILED"
    exit 1
fi