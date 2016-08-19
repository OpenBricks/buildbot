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
PIDFILE_BUILDBOT=$STAMPS/lock

BWLIMIT=100
XFERLOG=/tmp/rlog
RSYNCLOG=$LOGS/rsynclogs
STATUSLOG=$LOGS/statuslogs

DATE=`date +%Y%m%d`

log() {
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

sendlogs () {
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --log-file=$XFERLOG --partial $LOGS/$REPONAME/*.?z* $SYNCTARGET:/data/logs-buildbot"
  echo "Rsyncing build logs: $rsync_args" >> $RSYNCLOG
  rsync $rsync_args >> $RSYNCLOG 2>&1

  if [ $? -eq 0 ]; then
    log "rsync successful (logs)"
  else
    log "rsync failed (logs)"
  fi
}

sendsnapshot () {
  rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --log-file=$XFERLOG --partial $SNAPSHOTSD $SYNCTARGET:/data/snapshots/"
  echo "Rsyncing snapshot data: $rsync_args" >> $RSYNCLOG
  rsync $rsync_args >> $RSYNCLOG 2>&1

  if [ $? -eq 0 ]; then
    log "rsync successful (data)"
    rm -f $LOGS/rsynchfailed
  else
    log "rsync failed (data)"
    touch $LOGS/rsynchfailed
  fi
}

sendsnapshotlink () {
  if ! [ -f $LOGS/rsynchfailed ] ; then
    rsync_args="-t --size-only --bwlimit=$BWLIMIT --archive --delete --log-file=$XFERLOG --partial $SNAPSHOTS/* $SYNCTARGET:/data/snapshots"
    echo "Rsyncing snapshot links: $rsync_args" >> $RSYNCLOG
    rsync $rsync_args >> $RSYNCLOG 2>&1

    if [ $? -eq 0 ]; then
      log "rsync successful (links)"
    else
      log "rsync failed (links)"
    fi
  else
    log "rsync skipped (links)"
  fi
}


# Create directories
mkdir -p $SNAPSHOTS/$REPONAME $SNAPSHOTSD/$REPONAME $STAMPS/$REPONAME $LOGS/$REPONAME
log "Starting rsync to fry ..."

# Check for re-entry
if [ -r $PIDFILE ]; then
  log "Another rsync instance ($(cat $PIDFILE)) is running, aborting."
  exit 1
fi

/bin/echo -n $$ > $PIDFILE

# Move old rsync log
cat $RSYNCLOG >> $LOGS/$REPONAME/rsync.$DATE.log
date -R > $RSYNCLOG

echo "--------------------------------------------------------------------------------------" > $STATUSLOG
cat $LOGFILE >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
whoami >> $STATUSLOG
echo $HOME >> $STATUSLOG
echo $USER >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
#crontab -l >> $STATUSLOG
df -BM >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG

system_uptime_days=$(expr $(sed -e "s/\..*//" /proc/uptime) / 86400)
echo "System uptime: $system_uptime_days days" >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG

buildbot_pid=$(cat $PIDFILE_BUILDBOT)
if [ -n "$buildbot_pid" ]; then
  if ps -p $buildbot_pid > /dev/null; then
    echo "Buildbot instance $buildbot_pid alive." >> $STATUSLOG
  else
    echo "Buildbot instance $buildbot_pid is dead !!!" >> $STATUSLOG
  fi
  echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
fi

cat $STATUSLOG $LOGS/$REPONAME/rsync.$DATE.log | xz -z > $LOGS/$REPONAME/1-rsync.$DATE.log.xz

sendlogs
sendsnapshot
sendsnapshotlink

log "End of rsync"
rm -f $PIDFILE
exit 0
