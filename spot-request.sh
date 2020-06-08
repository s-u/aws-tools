#!/bin/bash

: ${AWS=aws}
EC2=ec2

while echo ":$1" | grep ^:- >/dev/null; do
    arg="x$1"
    shift
    if [ "$arg" = x-p ]; then
	prof="$1"
	shift
	if [ -z "$prof" ]; then
	    echo "ERROR: missing profile name in -p" >&2
	    exit 1
	fi
	AWS="$AWS --profile $prof"
    fi
    if [ "$arg" = x-a ]; then
	AMI="$1"
	shift
    fi
    if [ "$arg" = x-n ]; then
	INST_NAME="$1"
	shift
    fi
    if [ "$arg" = x-m ]; then
	MAXPRICE="$1"
	shift
    fi
    if [ "$arg" = x-h ]; then
	echo ''
	echo " Usage: $0 [-p <profle>] [-a <ami>] [-n <name>] [-m <price>] [<specs.json> [<volume-id>]]"
	echo ''
	echo ' Requests a spot instance according to the JSON specs file'
	echo ' attaches the volume (if provided) and queries the'
	echo ' public IP address.'
	echo ' There is no timeout limit for individual steps so it should'
	echo ' be run interactively.'
	echo ' The default specs are spot-default.json'
	echo ''
	echo ' All responses are logged to spot-request.log'
	echo ''
	echo ' Env vars: MAXPRICE - max price (defaults to 0.02)'
	echo '           AMI      - image to use (-a has higher priority)'
	echo '           AWS      - aws command (default is just aws)'
	echo ''
	exit 1
    fi
done

FN="$1"
shift
if [ -z "$FN" ]; then FN=spot-default.json; fi
if [ -z "$MAXPRICE" ]; then MAXPRICE=0.02; fi

if [ -n "$AMI" ]; then
    echo " - Modifying request to use AMI: $AMI"
    TF="spot.tmp"
    sed 's/"ImageId":.*/"ImageId": "'$AMI'",/' "$FN" > "$TF"
    FN="$TF"
fi

echo " - Using: $AWS $EC2"
echo " - Requesting instance according to $FN with max price $MAXPRICE"
sid=`$AWS $EC2 request-spot-instances --spot-price $MAXPRICE --launch-specification file://$FN | tee spot-request.log | sed -n 's/.*"SpotInstanceRequestId": "//p' | sed 's:".*::'`
if [ -z "$sid" ]; then
    echo "Something went wrong - result is empty"
    exit 1
fi

echo -n " - Accepted ($sid), waiting ."
while true; do
    iid=`$AWS $EC2 describe-spot-instance-requests --spot-instance-request-ids $sid| tee -a spot-request.log | sed -n 's/.*"InstanceId": "//p' | sed 's:".*::'`
    if [ -n "$iid" ]; then break; fi
    ## let's also check for low price
    if $AWS $EC2 describe-spot-instance-requests --spot-instance-request-ids $sid| grep price; then
	echo ''
	echo " Price too low (see above), re-run with MAXPRICE=... $0 $*"
	echo ''
        echo " - Cancelling $sid"
	$AWS $EC2 cancel-spot-instance-requests --spot-instance-request-ids $sid >> spot-request.log
	echo ''
	exit 1
    fi
    echo -n .
    sleep 3
done

echo " $iid"
echo -n " - Wait for running status "
while true; do
    if $AWS $EC2 describe-instance-status --instance-ids $iid | tee -a spot-request.log | grep '"Name": "running"' > /dev/null; then
	echo "OK"
	break
    fi
    echo -n .
    sleep 1
done

vdev=a
while (( "$#" )); do
    VOL="$1"
    shift
    vdev=`echo $vdev| tr 'a-z' 'b-z_'`
    echo -n " - Attach volume $VOL to /dev/xvd$vdev ... "
    ar=`$AWS $EC2 attach-volume --instance-id $iid --volume-id "$VOL" --device xvd$vdev | tee -a spot-request.log | sed -n 's/"State": "//p' | sed 's:".*::'`
    if [ -z "$ar" ]; then
	echo FAILED
	exit 1
    fi
    echo $ar
done

if [ -n "$INST_NAME" ]; then
    echo " - Tagging instance with Name $INST_NAME"
    $AWS $EC2 create-tags --resources "$iid" --tags Key=Name,Value="$INST_NAME" | tee -a spot-request.log
fi

echo -n " - IP address(es): "
ip=`$AWS $EC2 describe-instances --instance-ids $iid | sed -n 's/"PublicIp": "//p' | tee -a spot-request.log | sed 's:".*::'`
echo $ip

if $AWS $EC2 describe-instances --instance-ids $iid | grep '"Platform": "windows"' >/dev/null; then
    echo ' - This is a Windows, to get password:'
    echo "$AWS $EC2 get-password-data --instance-id $iid --priv-launch-key"
fi
echo ''

