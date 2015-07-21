#!/bin/sh
REPONAME=openbricks
REPOURL="https://github.com/OpenBricks/openbricks.git"
SYNCTARGET="buildbot@fry.geexbox.org"

BASE=$HOME/bot/buildbot
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
BUILD=$BASE/build
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
STAMPS=$BASE/stamps
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPSGET=$BASE/src/.stamps

BWLIMIT=90
XFERLOG=/tmp/rlog
BUILDLOG=$LOGS/rsynclogs


log() {
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

sendsnapshot () {
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=$XFERLOG --partial $LOGS/$REPONAME/*.?z* $SYNCTARGET:/data/logs-buildbot"
  log "Rsyncing build logs: $rsync_args"
  rsync $rsync_args >> $BUILDLOG 2>&1
  
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=$XFERLOG --partial $SNAPSHOTSD $SYNCTARGET:/data/snapshots/"
  log "Rsyncing snapshots: $rsync_args"  
  rsync $rsync_args >> $BUILDLOG 2>&1
  
  if [ $? -eq 0 ]; then
    log "rsync successful"
    rm -f $LOGS/rsynchfailed
  else
    log "rsync failed"
    touch $LOGS/rsynchfailed
  fi
}

sendsnapshotlink () {
  if ! [ -f $LOGS/rsynchfailed ] ; then
    rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=$XFERLOG --partial $SNAPSHOTS/* $SYNCTARGET:/data/snapshots"
    log "Rsyncing snapshot link: $rsync_args"
    rsync $rsync_args >> $BUILDLOG 2>&1
    
    if [ $? -eq 0 ]; then
      log "rsync successful (link)"
    else
      log "rsync failed (link)"
    fi
  fi
}


# Create directories
mkdir -p $SNAPSHOTS/$REPONAME $SNAPSHOTSD/$REPONAME $STAMPS/$REPONAME $LOGS/$REPONAME
log "Starting rsync to fry ..."

# Check for re-entry
if [ -r $STAMPS/lockrsync ]; then
  log "Another rsync instance (`cat $STAMPS/lockrsync`) is running, aborting."
  exit 1
fi

/bin/echo -n $$ > $STAMPS/lockrsync

sendsnapshot
sendsnapshotlink

log "End of rsync"
rm -f $STAMPS/lockrsync
exit 0
