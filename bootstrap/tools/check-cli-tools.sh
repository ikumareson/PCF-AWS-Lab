#!/bin/bash

which yq > /dev/null
if [ "$?" -ne "0" ]; then
	echo "please install YQ (using brew if using OSX)"
	exit 7
fi
which jq > /dev/null
if [ "$?" -ne "0" ]; then
	echo "please install JQ (using brew if using OSX)"
	exit 8
fi

which az > /dev/null
if [ "$?" -ne "0" ]; then
	echo "please install AZ cli (using brew if using OSX)"
	exit 9
fi
