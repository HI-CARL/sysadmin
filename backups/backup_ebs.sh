#!/bin/bash

# Create backups/snapshots of EBS volumes on EC2 instances on daily cron.
# Requires EC2 CLI API tools to be available (and subsequently Java/OpenJDK)
#
# @author Dan Jones <dan@danneh.org>

##### Start Config #####
EC2_PRIMARY_KEY=
EC2_CERTIFICATE=

# no trailing / please..
EC2_API_ROOT=/ebs/bin/ec2-api-tools

SNAPSHOTS_TO_KEEP=50
##### End Config #####

export EC2_HOME=$EC2_API_ROOT
export JAVA_HOME=/usr

EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_NAME=$($EC2_API_ROOT/bin/ec2-describe-tags \
                        -K $EC2_PRIMARY_KEY \
                        -C $EC2_CERTIFICATE \
                        --region $EC2_REGION \
                        --filter "resource-type=instance" \
                        --filter "resource-id=$INSTANCE_ID" \
                        --filter "key=Name" | awk '{for (i=5; i<=NF; i++) { printf("%s ", $i)}}')

VOLUME_LIST=$(${EC2_API_ROOT}/bin/ec2-describe-volumes \
                        -C $EC2_CERTIFICATE \
                        -K $EC2_PRIMARY_KEY \
                        --region $EC2_REGION \
                        | grep ${INSTANCE_ID} \
                        | awk '{ print $2 ":" $4 }')

for volume in $(echo $VOLUME_LIST); do
        # EBS volume ID
        vol=`echo $volume | cut -d':' -f1`

        # Local Device
        dev=$($EC2_API_ROOT/bin/ec2-describe-tags \
                        -K $EC2_PRIMARY_KEY \
                        -C $EC2_CERTIFICATE \
                        --region $EC2_REGION \
                        --filter "resource-type=volume" \
                        --filter "resource-id=$vol" \
                        --filter "key=Device" | awk '{ print $5 }')

        # Mount Point
        mnt=`df | grep $dev | awk '{ print $6 }'`

        # Filesystem Type
        fs=`mount | grep $dev | awk '{ print $5 }'`

        echo "**** Snapshotting $mnt ($fs:$dev) ($vol) ****"

        if [ "$fs" == "xfs" -a "$mnt" != "/" ]; then
                # don't xfs_freeze the root partition. also, don't xfs_freeze a non-xfs partition!
                xfs_freeze -f $mnt
        fi

        ${EC2_API_ROOT}/bin/ec2-create-snapshot \
                -C $EC2_CERTIFICATE \
                -K $EC2_PRIMARY_KEY \
                --region $EC2_REGION \
                --description "$INSTANCE_NAME (Mount Point: $mnt) (Date: $(date +'%Y-%m-%d %H:%M:%S'))" \
                $vol

        if [ "$fs" == "xfs" -a "$mnt" != "/" ]; then
                xfs_freeze -u $mnt
        fi

        echo "**** Cleaning up old snapshots..."

        SNAPSHOT_LIST=$(${EC2_API_ROOT}/bin/ec2-describe-snapshots \
                                -C $EC2_CERTIFICATE \
                                -K $EC2_PRIMARY_KEY \
                                --region $EC2_REGION \
                                | grep $vol \
                                | sort -k5 -r \
                                | awk '{ print $2 }')
        count=0
        for snapshot in $(echo $SNAPSHOT_LIST); do
                (( count++ ))
                if [ $count -gt $SNAPSHOTS_TO_KEEP ]; then
                        ${EC2_API_ROOT}/bin/ec2-delete-snapshot \
                                -C $EC2_CERTIFICATE \
                                -K $EC2_PRIMARY_KEY \
                                --region $EC2_REGION \
                                $snapshot
                fi
        done

done
