#!/bin/bash
# Get instance ID, Instance AZ, Volume ID and Volume AZ
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=us-east-1

VOLUME_ID=$(aws ec2 describe-volumes --region $AWS_REGION --filter "Name=tag:Name,Values=DL-kelp-checkpoints" --query "Volumes[].VolumeId" --output text)
VOLUME_AZ=$(aws ec2 describe-volumes --region $AWS_REGION --filter "Name=tag:Name,Values=DL-kelp-checkpoints" --query "Volumes[].AvailabilityZone" --output text)

# Proceed if Volume Id is not null or unset
if [ "$VOLUME_ID" ]; then
		# Wait until any previous instances shut down
		aws ec2 wait volume-available --region $AWS_REGION --volume-id "$VOLUME_ID"

		# Check if the Volume AZ and the instance AZ are same or different.
		# If they are different, create a snapshot and then create a new volume in the instance's AZ.
		if [ "$VOLUME_AZ" != "$INSTANCE_AZ" ]; then
				SNAPSHOT_ID=$(aws ec2 create-snapshot \
						--region $AWS_REGION \
						--volume-id "$VOLUME_ID" \
						--description "$(date +"%D %T")" \
						--tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=DL-kelp-checkpoints-snapshot}]' \
						--query SnapshotId --output text)

				aws ec2 wait --region $AWS_REGION snapshot-completed --snapshot-ids "$SNAPSHOT_ID"
				aws ec2 --region $AWS_REGION  delete-volume --volume-id "$VOLUME_ID"

				VOLUME_ID=$(aws ec2 create-volume \
						--region $AWS_REGION \
								--availability-zone "$INSTANCE_AZ" \
								--snapshot-id "$SNAPSHOT_ID" \
						--volume-type gp2 \
						--tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=DL-kelp-checkpoints}]' \
						--query VolumeId --output text)
				aws ec2 wait volume-available --region $AWS_REGION --volume-id "$VOLUME_ID"
		fi
		# Attach volume to instance
		aws ec2 attach-volume \
			--region $AWS_REGION --volume-id "$VOLUME_ID" \
			--instance-id "$INSTANCE_ID" --device /dev/sdf
		sleep 10

		# Mount volume and change ownership, since this script is run as root
		mkdir -p /dltraining
		mount /dev/xvdf /dltraining
		chown -R ubuntu: /dltraining/
		cd /home/ubuntu/ || exit

    # Change the docker image installation cache directory
		sed -i 'N;$s/}\n}/},\n    "data-root": "\/dltraining\/docker-data"\n}/' /etc/docker/daemon.json
		systemctl daemon-reload
		systemctl restart docker

		# Get training code
		git clone https://github.com/tayden/uav-classif.git
		chown -R ubuntu: uav-classif
		cd uav-classif/scripts/species || exit
		mkdir -p ./train_input/data
		mount --bind /dltraining/species/data ./train_input/data
		mkdir -p ./train_output
		mount --bind /dltraining/species/train_output ./train_output
fi

# After training, clean up by cancelling spot requests and terminating itself
# shellcheck disable=SC2034
SPOT_FLEET_REQUEST_ID=$(aws ec2 describe-spot-instance-requests --region $AWS_REGION --filter "Name=instance-id,Values='$INSTANCE_ID'" --query "SpotInstanceRequests[].Tags[?Key=='aws:ec2spot:fleet-request-id'].Value[]" --output text)
# aws ec2 cancel-spot-fleet-requests --region $AWS_REGION --spot-fleet-request-ids $SPOT_FLEET_REQUEST_ID --terminate-instances