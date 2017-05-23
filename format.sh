#!/bin/bash
#############################################################################################
# Script:       datadisk.sh
# Author:       R. Jamieson
# Version:      20170428-1
# Description:  Creates a filesystem on an unused data disk
# Usage:        datadisk.sh
#		MOUNTNUM={n} datadisk
# Summary:
#		This script scans for unpartitioned disks and will create a /datadrive{n} 
#		filesystem on them. 
#		First unpartioned ( "unused" ) disk will be partitioned ( single partition,
#		using entire disk ) and have a filesystem called /datadrive1 created and
#		mounted on that partition.
#               i)   Check datadisk device exists
#               ii)  Read current disk label : fdisk /dev/sdd : Check for
#                    "Device does not contain a recognized partition table"
#               iii) Create a primary partition	( using entire disk )
#               iv)  Check for primary partition
#               v)   Create Filesystem ( and put a label on it )
#               vi)  Update fstab - and mount the fileystem
#               vii) Check filesystem mounted
# Variable:	MOUNTNUM: For numbering first mountpoint, see: MOUNTPOINT=/datadrive$MOUNTNUM
#############################################################################################


#############################################################################################
# Functions

# Grab current disk partition details using fdisk
function ShowDiskInfo {
   DISK_DEV=$1  # eg: /dev/sdd
   DISK_INFO=$(fdisk $DISK_DEV <<EOT 2>&1
p
q
EOT
)
   RC=$?
   if [ "$RC" != 0 ] ; then
      #echo "FAILURE: Could not get disk info"
      return 1
   fi
   echo "$DISK_INFO"
}

# Checks specified disk device does not contain a partition table already
function CheckUnused {
   DISK_DEV=$1
   echo '----------------------------------------------------------------------------------'
   DISK_INFO=$(ShowDiskInfo $DISK_DEV)
   RC=$?
   echo "$DISK_INFO"
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not get disk info"
      return 1
   fi
   NOTUSEDSTRING="Device does not contain a recognized partition table"
   echo "$DISK_INFO" | grep -q "$NOTUSEDSTRING"
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: DISK_IS_USED : Disk is in use - expected label to contain: \"$NOTUSEDSTRING\""
      return 1
   else
      echo "SUCCESS: Disk label DOES NOT contain: \"$NOTUSEDSTRING\""
   fi
   PARTITION_INFO=$(echo "$DISK_INFO" | grep ^$DISK_DEV)
   RC=$?
   if [ "$RC" = 0 ] ; then
      echo "FAILURE: DISK_IS_USED : Disk is in use - contains partitions"
      echo "$PARTITION_INFO"
      return 1
   else
      echo "SUCCESS: Did not find any partition on the disk"
   fi
}

# Creates a primary partition (using entire disk) , on specified disk
function MakePrimaryPartition {
   DISK_DEV=$1
   fdisk $DISK_DEV <<EOT
n
p



p
w
EOT
}

# Checks that a primary partition exists on the specified disk
function CheckPrimaryPartition {
   DISK_DEV=$1
   DISK_INFO=$2
   PARTITION=${DISK_DEV}1
   PARTITION_RECORD=$(echo "$DISK_INFO" | grep ^"$PARTITION ")
   RC=$?
   if [ "$RC" = 0 ] ; then
      echo "SUCCESS: Partition found : $PARTITION"
      echo "$PARTITION_RECORD"
   else
      echo "FAILURE: Did not find the partition on the disk: $PARTITION"
      return 1
   fi
}

# Creates the filesystem and mounts it
function DoFilesystem {
   PARTITION=$1
   MOUNTPOINT=$2
   FSTYPE=ext4
   echo "Make $FSTYPE filesystem ($MOUNTPOINT) on partition $PARTITION"
   mkfs -t $FSTYPE -L $MOUNTPOINT $PARTITION
   RC=$?
   if [ "$RC" = 0 ] ; then
      echo "SUCCESS: Created $FSTYPE filesystem on $PARTITION"
   else
      echo "FAILURE: Could not create $FSTYPE filesystem on $PARTITION"
      return 1
   fi
   echo "Make mount point : $MOUNTPOINT"
   mkdir $MOUNTPOINT
   RC=$?
   if [ "$RC" = 0 ] ; then
      echo "SUCCESS: Created mount point : $MOUNTPOINT"
      ls -ld $MOUNTPOINT
   else
      echo "FAILURE: Could not create mount point : $MOUNTPOINT"
      return 1
   fi
   echo "Backup /etc/fstab to /etc/fstab.ORIG"
   cp /etc/fstab /etc/fstab.ORIG
   RC=$?
   if [ "$RC" = 0 ] ; then
      echo "SUCCESS: Created Backup /etc/fstab to /etc/fstab.ORIG"
      ls -ltr /etc/fstab*
   else
      echo "FAILURE: Could not Backup /etc/fstab to /etc/fstab.ORIG"
      return 1
   fi

   echo "Get all block device info"
   BLOCKDEV_INFO=$(blkid -o list)
   RC=$?
   echo "$BLOCKDEV_INFO"
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not get block device info :  blkid -o list"
      return 1
   fi

   echo "Get block device info for the new partition: $PARTITION"
   THE_BLOCKDEV=$(echo "$BLOCKDEV_INFO" | grep ^"$PARTITION " | grep "$MOUNTPOINT ")
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not find device info for the new partition: $PARTITION"
      return 1
   fi

   THE_UUID=$(echo "$THE_BLOCKDEV" | awk '{print $NF}')

   echo "UUID=$THE_UUID $MOUNTPOINT     $FSTYPE defaults        1 2" >>/etc/fstab
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not update /etc/fstab"
      return 1
   fi

   echo "Mount the filesystem : $MOUNTPOINT"
   mount "$MOUNTPOINT"
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not mount the filesystem : $MOUNTPOINT"
      return 1
   else
      echo "SUCCESS: Mounted the filesystem : $MOUNTPOINT"
   fi

}



function MakeDataDisk {
   DISK_DEV=$1
   MOUNTPOINT=$2
   echo '----------------------------------------------------------------------------------'
   # Check datadisk device exists
   echo "DATADISK DEVICE"
   if [ ! -b "$DISK_DEV" ] ; then
      echo "FAILURE: No such device $DISK_DEV"
      return 1
   else
      echo "SUCCESS: Found block device file $DISK_DEV"
   fi

   echo '----------------------------------------------------------------------------------'
   echo "CHECK DISK UNUSED"
   CheckUnused $DISK_DEV        # Double check during testing - may remove later.
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Disk appears to be in used - or used"
      return 1
   fi

   # Create a primary partition
   # Check for primary partition
   echo '----------------------------------------------------------------------------------'
   echo "MAKE PRIMARY PARTITION"
   MakePrimaryPartition $DISK_DEV

   # Re-check current disk label : Should be a new primary partition
   echo '----------------------------------------------------------------------------------'
   echo "DISK INFO"
   DISK_INFO=$(ShowDiskInfo $DISK_DEV)
   RC=$?
   echo "$DISK_INFO"
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not get disk info"
      return 1
   fi

   echo '----------------------------------------------------------------------------------'
   echo "CHECK PRIMARY PARTITION"
   CheckPrimaryPartition $DISK_DEV "$DISK_INFO"
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not create the new partition"
      return 1
   fi

   echo '----------------------------------------------------------------------------------'
   echo "CREATE FILESYSTEM: $MOUNTPOINT on PARTITION $PARTITION"
   DoFilesystem $PARTITION $MOUNTPOINT
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "FAILURE: Could not create filesystem $MOUNTPOINT on partition $PARTITION"
      return 1
   fi

   echo "SUCCESS: Filesystem created and mounted"
   df -h $MOUNTPOINT
}
# End of functions
#############################################################################################

#############################################################################################
# Main prog start
PROG=$0
PROG_SCRIPT=$(basename $PROG)
PROG_NAME=$(echo $PROG_SCRIPT | cut -d '.' -f1)
DATADRIVE_COUNT=$(lsblk | grep /datadrive | wc -l)
(( NEXT_MOUNTNUM = $DATADRIVE_COUNT + 1 ))
MOUNTNUM=${MOUNTNUM:-$NEXT_MOUNTNUM}	# For numbering first mountpoint - see:  MOUNTPOINT=/datadrive$MOUNTNUM

echo '--------------------------------------------------------------------------------------------'
echo "Running: $PROG"
echo "$(date)"
echo 
echo

DISK_EXCLUDES="/dev/sda|/dev/sdb"
DISKLIST=$(fdisk -l | grep ^"Disk /")
echo "DISKLIST:"
echo "$DISKLIST"

ALL_DISKS=$(echo "$DISKLIST" | awk '{print $2}' | cut -d ':' -f1 | sort)
echo "ALL_DISKS: " $ALL_DISKS
echo "DISK_EXCLUDES: /dev/mapper and " $DISK_EXCLUDES
DATADISKS=$(echo "$ALL_DISKS" | grep -vE ^"$DISK_EXCLUDES"$ | grep -v ^/dev/mapper )
echo "DATADISKS: " $DATADISKS
echo "MOUNTNUM: $MOUNTNUM , ie: first mountpoint = /datadrive$MOUNTNUM"
echo
echo "Will now partition and create filesystems on all datadisks (fails is datadisk is used)"

for DATADISK in $DATADISKS ; do
   DISK_DEV=$DATADISK
   PARTITION=${DISK_DEV}1
   MOUNTPOINT=/datadrive$MOUNTNUM

   echo '----------------------------------------------------------------------------------'
   echo "DATADISK:      $DATADISK"
   echo "DISK_DEV: $DISK_DEV"
   echo "PARTITION:     $PARTITION"
   echo "MOUNTPOINT:       $MOUNTPOINT"

   echo "CHECK DISK UNUSED"
   CheckUnused $DISK_DEV
   RC=$?
   if [ "$RC" != 0 ] ; then
      echo "WARNING: Disk appears to be in used - or used - WILL SKIP THIS DISK ($DATADISK)"
   else
      echo "SUCCESS: Disk unused - will create filesystem on it now"
      MakeDataDisk $DISK_DEV $MOUNTPOINT
      RC=$?
      if [ "$RC" != 0 ] ; then
         echo "FAILURE: MakeDataDisk $DISK_DEV $MOUNTPOINT"
         exit 1
      else
         echo "SUCCESS: MakeDataDisk $DISK_DEV $MOUNTPOINT"
         (( MOUNTNUM = $MOUNTNUM + 1 ))
      fi
   fi

done

echo
echo
echo '--------------------------------------------------------------------------------------------'
echo "Finished: $PROG"
echo "$(date)"
echo '--------------------------------------------------------------------------------------------'
