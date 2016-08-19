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

remove_source () {
  if [ ! -e $SOURCES/$1/$2.bad ]; then
    mv -f $SOURCES/$1/$2 $SOURCES/$1/$2.bad
    rm $STAMPSGET/$1/.*.get $STAMPSGET/$1/*.ok

    echo "Removing $1/$2" >> $STATUSLOG
    echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
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
echo "WHOAMI: $(whoami)" >> $STATUSLOG
echo "  USER: $USER" >> $STATUSLOG
echo "  HOME: $HOME" >> $STATUSLOG
echo "   PWD: $PWD" >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
crontab -l >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
df -BM >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG

uptime_limit=21
buildbot_state="idle"
buildbot_pid=$(cat $PIDFILE_BUILDBOT 2>/dev/null)
if [ -n "$buildbot_pid" ]; then
  if ps -p $buildbot_pid >/dev/null; then
    uptime_limit=28
    buildbot_state="active"
  else
    uptime_limit=0
    buildbot_state="dead"
  fi
  echo "Buildbot instance ${buildbot_pid} is ${buildbot_state}." >> $STATUSLOG
  echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
fi

system_uptime_days=$(expr $(sed -e "s/\..*//" /proc/uptime) / 86400)
echo "System uptime: $system_uptime_days days, reboot after $uptime_limit days" >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG

remove_source "gcc-linaro" "gcc-linaro-4.9-2016.02.tar.xz"

cat $STATUSLOG $LOGS/$REPONAME/rsync.$DATE.log | xz -z > $LOGS/$REPONAME/1-rsync.$DATE.log.xz

sendlogs
sendsnapshot
sendsnapshotlink

log "End of rsync"

# Reboot system periodically
if [ $system_uptime_days -gt $uptime_limit ]; then
  sudo reboot
fi

rm -f $PIDFILE
exit 0
