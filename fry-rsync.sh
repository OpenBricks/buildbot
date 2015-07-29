#!/bin/sh
REPONAME=openbricks
REPOURL="https://github.com/OpenBricks/openbricks.git"
SYNCTARGET="buildbot@fry.geexbox.org"

BASE=/home/geexbox/bot/buildbot

BUILD=$BASE/build
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
STAMPSGET=$BASE/src/.stamps
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPS=$BASE/stamps
PIDFILE=$STAMPS/lockrsync

BWLIMIT=100
XFERLOG=/tmp/rlog
RSYNCLOG=$LOGS/rsynclogs

DATE=`date +%Y%m%d`

log() {
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

sendlogs () {
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --log-file=$XFERLOG --partial $LOGS/$REPONAME/*.?z* $SYNCTARGET:/data/logs-buildbot"
  log "Rsyncing build logs: $rsync_args"
  rsync $rsync_args >> $RSYNCLOG 2>&1
}

sendsnapshot () {  
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --log-file=$XFERLOG --partial $SNAPSHOTSD $SYNCTARGET:/data/snapshots/"
  log "Rsyncing snapshot data: $rsync_args"  
  rsync $rsync_args >> $RSYNCLOG 2>&1
  
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
    log "Rsyncing snapshot links: $rsync_args"
    rsync $rsync_args >> $RSYNCLOG 2>&1
    
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
if [ -r $PIDFILE ]; then
  log "Another rsync instance (`cat $PIDFILE`) is running, aborting."
  exit 1
fi

/bin/echo -n $$ > $PIDFILE

# Move old rsync log
cat $RSYNCLOG >> $LOGS/$REPONAME/rsync.$DATE.log
cat $LOGFILE >> $LOGS/$REPONAME/rsync.$DATE.log
tar -caf $LOGS/$REPONAME/2-scripts.xz /home/geexbox/*.sh
rm -f $RSYNCLOG
xz -z < $LOGS/$REPONAME/rsync.$DATE.log > $LOGS/$REPONAME/1-rsync.$DATE.log.xz

sendlogs
sendsnapshot
sendsnapshotlink

log "End of rsync"
rm -f $PIDFILE
exit 0
