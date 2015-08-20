# Copyright 2013 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS-IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Mounts any attached persistent and ephemeral disks non-boot disks

set -e

# Install software RAID configuration tools
DEBIAN_FRONTEND=noninteractive install_application "mdadm"

# Create the software RAID volume on all four Local SSD drives
mdadm --create --verbose /dev/md0 --level=stripe --raid-devices=4 /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Get a list of disks from the metadata server.
BASE_DISK_URL='http://metadata.google.internal/computeMetadata/v1beta1/instance/disks/'
DISK_PATHS=$(curl ${BASE_DISK_URL})
MOUNTED_DISKS=()

# Mount the software RAID volume
DISK_ID="/dev/md0"
DATAMOUNT="/mnt/md0"
mkdir -p ${DATAMOUNT}
MOUNTED_DISKS+=(${DATAMOUNT})
echo "Mounting '${DISK_ID}' under mount point '${DATAMOUNT}'..."
MOUNT_TOOL=/usr/share/google/safe_format_and_mount
${MOUNT_TOOL} -m 'mkfs.ext4 -F' ${DISK_ID} ${DATAMOUNT}

for DISK_PATH in ${DISK_PATHS}; do
  # Use the metadata server to determine the official index/name of each disk.
  DISK_NAME=$(curl ${BASE_DISK_URL}${DISK_PATH}device-name)
  DISK_INDEX=$(curl ${BASE_DISK_URL}${DISK_PATH}index)
  DISK_TYPE=$(curl ${BASE_DISK_URL}${DISK_PATH}type)

  # Index '0' is the boot disk and is thus already mounted.
  if [[ "${DISK_INDEX}" == '0' ]]; then
    echo "Boot disk is ${DISK_NAME}; will not attempt to mount it."
    continue
  fi

  if [[ "${DISK_TYPE}" == 'EPHEMERAL' ]]; then
    echo "Skipping Ephemeral Disk $(DISK_NAME) assuming it is part of the software RAID volume."
    continue
    DISK_PREFIX='ed'
  elif [[ "${DISK_TYPE}" == 'PERSISTENT' ]]; then
    DISK_PREFIX='pd'
  fi

  # The metadata-specified 'name' can be converted to a disk 'id' by prepending
  # 'google-' and finding it under /dev/disk/by-id.
  DISK_ID="/dev/disk/by-id/google-${DISK_NAME}"
  echo "Resolved disk name '${DISK_NAME}' to expected path '${DISK_ID}'."

  # We will name the mount-point after the official 'disk index'; this means
  # there will be no mounted disk with suffix '0' since '0' is the boot disk.
  DATAMOUNT="/mnt/${DISK_PREFIX}${DISK_INDEX}"
  mkdir -p ${DATAMOUNT}
  MOUNTED_DISKS+=(${DATAMOUNT})
  echo "Mounting '${DISK_ID}' under mount point '${DATAMOUNT}'..."
  MOUNT_TOOL=/usr/share/google/safe_format_and_mount
  ${MOUNT_TOOL} -m 'mkfs.ext4 -F' ${DISK_ID} ${DATAMOUNT}

  # Idempotently update /etc/fstab
  if cut -d '#' -f 1 /etc/fstab | grep -qvw ${DATAMOUNT}; then
    DISK_UUID=$(blkid ${DISK_ID} -s UUID -o value)
    MOUNT_ENTRY=($(grep -w ${DATAMOUNT} /proc/mounts))
    # Taken from /usr/share/google/safe_format_and_mount
    MOUNT_OPTIONS='defaults,discard'
    echo "UUID=${DISK_UUID} ${MOUNT_ENTRY[@]:1:2} ${MOUNT_OPTIONS} 0 2 \
        # added by bdutil" >> /etc/fstab
  fi
done

# If disks are mounted use the first one to hold target of symlink /hadoop
if (( ${#MOUNTED_DISKS[@]} )); then
  MOUNTED_HADOOP_DIR=${MOUNTED_DISKS[0]}/hadoop
  mkdir -p ${MOUNTED_HADOOP_DIR}
  if [[ ! -d /hadoop ]]; then
    ln -s ${MOUNTED_HADOOP_DIR} /hadoop
  fi
fi
