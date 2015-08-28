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
DISK_ID="/dev/md0"
mdadm --create --verbose ${DISK_ID} --level=stripe --raid-devices=4 /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Mount the software RAID volume
DATAMOUNT="/mnt/md0"
mkdir -p ${DATAMOUNT}
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

# If disks are mounted use the first one to hold target of symlink /hadoop
if (( ${#MOUNTED_DISKS[@]} )); then
  MOUNTED_HADOOP_DIR=${MOUNTED_DISKS[0]}/hadoop
  mkdir -p ${MOUNTED_HADOOP_DIR}
  if [[ ! -d /hadoop ]]; then
    ln -s ${MOUNTED_HADOOP_DIR} /hadoop
  fi
fi
