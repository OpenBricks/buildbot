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
  log "Another rsync instance (`cat $PIDFILE`) is running, aborting."
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
#sudo ls -lisa /var/spool/cron/crontabs >> $STATUSLOG
#sudo cat /var/spool/cron/crontabs/geexbox >> $STATUSLOG
CRONTAB=/tmp/crontab.tmp
CRONTAB2=/tmp/crontab2.tmp
crontab -l > $CRONTAB
if ! grep -q "reset-buildbot\.sh" $CRONTAB; then
  grep "^#" $CRONTAB > $CRONTAB2
  cat >> $CRONTAB2 <<EOF

0 * * * *	/home/geexbox/update-buildbot.sh
2 * * * *	/home/geexbox/buildbot/buildbot.sh
4 * * * *	/home/geexbox/buildbot/fry-rsync.sh
@reboot		/home/geexbox/buildbot/reset-buildbot.sh
EOF
  cat $CRONTAB2 >> $STATUSLOG
fi
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG
crontab -l >> $STATUSLOG
echo "--------------------------------------------------------------------------------------" >> $STATUSLOG

cat $STATUSLOG $LOGS/$REPONAME/rsync.$DATE.log | xz -z > $LOGS/$REPONAME/1-rsync.$DATE.log.xz

sendlogs
sendsnapshot
sendsnapshotlink

log "End of rsync"
rm -f $PIDFILE
exit 0
