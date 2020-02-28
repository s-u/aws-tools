#!/bin/bash

if [ "x$1" = x-h ]; then
    echo ''
    echo " Usage: $0 [<specs.json> [<volume-id>]]"
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
    echo '           AMI      - image ot use (overrides the json)'
    echo ''
    exit 1
fi

FN="$1"
if [ -z "$FN" ]; then FN=spot-default.json; fi
if [ -z "$MAXPRICE" ]; then MAXPRICE=0.02; fi
VOL="$2"

if [ -n "$AMI" ]; then
    TF="spot.tmp"
    sed 's/"ImageId":.*/"ImageId": "'$AMI'",/' "$FN" > "$TF"
    FN="$TF"
fi

echo " - Requesting instance according to $FN with max price $MAXPRICE"
sid=`aws ec2 request-spot-instances --spot-price $MAXPRICE --launch-specification file://$FN | tee spot-request.log | sed -n 's/.*"SpotInstanceRequestId": "//p' | sed 's:".*::'`
if [ -z "$sid" ]; then
    echo "Something went wrong - result is empty"
    exit 1
fi

echo -n " - Accepted ($sid), waiting ."
while true; do
    iid=`aws ec2 describe-spot-instance-requests --spot-instance-request-ids $sid| tee -a spot-request.log | sed -n 's/.*"InstanceId": "//p' | sed 's:".*::'`
    if [ -n "$iid" ]; then break; fi
    ## let's also check for low price
    if aws ec2 describe-spot-instance-requests --spot-instance-request-ids $sid| grep price; then
	echo ''
	echo " Price too low (see above), re-run with MAXPRICE=... $0 $*"
	echo ''
        echo " - Cancelling $sid"
	aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $sid >> spot-request.log
	echo ''
	exit 1
    fi
    echo -n .
    sleep 3
done

echo " $iid"
echo -n " - Wait for running status "
while true; do
    if aws ec2 describe-instance-status --instance-ids $iid | tee -a spot-request.log | grep '"Name": "running"' > /dev/null; then
	echo "OK"
	break
    fi
    echo -n .
    sleep 1
done

if [ -z "$VOL" ]; then
    echo " - No volume supplied, skipping attach step"
else
    echo -n " - Attach volume $VOL to /dev/xvdb ... "
    ar=`aws ec2 attach-volume --instance-id $iid --volume-id "$VOL" --device xvdb | tee -a spot-request.log | sed -n 's/"State": "//p' | sed 's:".*::'`
    if [ -z "$ar" ]; then
	echo FAILED
	exit 1
    fi
    echo $ar
fi

echo -n " - IP address(es): "
ip=`aws ec2 describe-instances --instance-ids $iid | sed -n 's/"PublicIp": "//p' | tee -a spot-request.log | sed 's:".*::'`
echo $ip

if aws ec2 describe-instances --instance-ids $iid | grep '"Platform": "windows"' >/dev/null; then
    echo ' - This is a Windows, to get password:'
    echo "aws ec2 get-password-data --instance-id $iid --priv-launch-key"
fi
echo ''

