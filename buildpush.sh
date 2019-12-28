#!/bin/bash

cd `dirname $0`

version=$1
repo=$2
if [ -z "$version" ];then
    echo 'usage: buildpush.sh <version i.e. - 1.5>'
    exit 1
fi

if [ -z "$repo" ];then
    repo='phillsv87/ftps3'
fi

tag="$repo:$version"

echo "Building $tag"
docker build -t $tag .
if [ "$?" != "0" ];then
    echo 'Build failed'
    exit 1
fi
echo "Build Success - $tag"

echo "Pushing $tag"
docker push $tag
if [ "$?" != "0" ];then
    echo 'Push failed'
    exit 1
fi
echo "Push Success - $tag"

echo "$version" > './current-version.txt'