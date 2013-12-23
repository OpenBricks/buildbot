#!/bin/sh
BASE=/home/geexbox/bot/buildbot
REPONAME=openbricks
REPOURL="http://hg.openbricks.org/openbricks"
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
BUILD=$BASE/build
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
STAMPS=$BASE/stamps
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPSGET=$BASE/src/.stamps
BUILDLOG=$LOGS/rsynclogs

BWLIMIT=100


log()
{
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

sendsnapshot ()
{
  if [ -f $LOGS/rsynchfailed ] ; then
    rm $LOGS/rsynchfailed
  fi
  log "Rsyncing snapshots to fry"
  log "rsync -t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=/tmp/rlog --partial $SNAPSHOTSD buildbot@fry.geexbox.org:/data/snapshots"
  rsync -t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=/tmp/rlog --partial $SNAPSHOTSD buildbot@fry.geexbox.org:/data/snapshots/ >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "rsync successful"
  else
    log "rsync failed"
    touch $LOGS/rsynchfailed
  fi
}

sendsnapshotlink ()
{
  if ! [ -f $LOGS/rsynchfailed ] ; then
    log "Rsyncing snapshots (link) to fry"
    log "rsync -t --size-only --bwlimit=75 --archive --delete --log-file=/tmp/rlog $SNAPSHOTS/* buildbot@fry.geexbox.org:/data/snapshots"
    rsync -t --size-only --bwlimit=75 --archive --delete --log-file=/tmp/rlog --partial $SNAPSHOTS/* buildbot@fry.geexbox.org:/data/snapshots >> $BUILDLOG 2>&1
    if [ $? -eq 0 ]; then
      log "rsync successful (link)"
    else
      log "rsync failed (link)"
    fi
  fi
}

mkdir -p $BUILD $SOURCES $SNAPSHOTS $SNAPSHOTSD $STAMPS/$REPONAME $LOGS $BASE/src/.stamps
log "Starting rsync to fry ..."
if [ -r $STAMPS/lockrsync ]; then
  log "Another rsync instance (`cat $STAMPS/lockrsync`) is running, aborting."
  exit 1
else
  /bin/echo -n $$ > $STAMPS/lockrsync
fi

sendsnapshot
sendsnapshotlink

log "End of rsync"
rm -f $STAMPS/lockrsync