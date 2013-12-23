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

if [ -r $STAMPS/$REPONAME/rev ]; then
  OLDREV=`cat $STAMPS/$REPONAME/rev`
fi
DATE=`date +%Y%m%d`

log()
{
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

mailfail()
{
cat > /tmp/mesg.txt <<EOF
Hi,

I was trying to build '$NAME', but something went wrong. The build
failed at '$1' stage,
----------

I was building from the $REPONAME repository at $REV revision on $DATE.
Attached, the log messages

buildbot
EOF

mpack -s "[buildbot] $NAME failed to build" -d /tmp/mesg.txt $BUILDLOG.bz2 tomlohave@gmail.com nicknickolaev@gmail.com openbricks-devel@googlegroups.com r.ihle@s-t.de

}

sendsnapshot ()
{
  if [ -f $LOGS/rsynchfailed ] ; then
    rm $LOGS/rsynchfailed
  fi
  log "Rsyncing snapshots to fry"
  log "rsync -t --size-only --bwlimit=75 --archive --delete --log-file=/tmp/rlog --partial $SNAPSHOTSD buildbot@fry.geexbox.org:/data/snapshots"
  rsync -t --size-only --bwlimit=75 --archive --delete --log-file=/tmp/rlog --partial $SNAPSHOTSD buildbot@fry.geexbox.org:/data/snapshots/ >> $BUILDLOG 2>&1
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
log "Starting"
if [ -r $STAMPS/lock ]; then
  log "Another buildbot instance (`cat $STAMPS/lock`) is running, aborting."
  exit 1
else
  /bin/echo -n $$ > $STAMPS/lock
  rm -Rf $BUILD/*
fi
if [ ! -d $REPO ]; then
  log "Cloning repo"
  hg clone $REPOURL $REPO > /dev/null 2>&1
else
  log "Pulling repo"
  (cd $REPO; hg pull -u > /dev/null 2>&1)
fi
REV=`hg identify $REPO`
if [ "$REV" = "$OLDREV" ]; then
  log "Nothing new"
else
  log "Found new rev $REV, rebuilding everything"
  rm -f $STAMPS/$REPONAME/*
  echo $REV > $STAMPS/$REPONAME/rev
fi

# build docs
cd $BUILD
NAME=docs
mkdir -p $LOGS/$REPONAME
BUILDLOG="$LOGS/$REPONAME/$NAME.$DATE.log"
log "Building $NAME"
if [ ! -d "$NAME" ]; then
  log "Cloning $NAME"
  rm -f $STAMPS/$NAME
  hg clone $REPO $NAME > $BUILDLOG
fi
rm -f "$BUILDLOG"
cd $NAME
hg update -C >> $BUILDLOG 2>&1
hg pull -u >> $BUILDLOG 2>&1
cd DOCS
make clean >> $BUILDLOG 2>&1
if [ $? -ne 0 ]; then
  log "$NAME clean failed"
else
  make >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "$NAME build successful"
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME/$DATE"
    cp -PR *.html *.pdf images "$SNAPSHOTS/$REPONAME/$NAME/$DATE/"
    cp -P $BASE/src/docs/*.png "$SNAPSHOTS/$REPONAME/$NAME/$DATE/images/"
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
  else
    log "$NAME build failed"
  fi
fi

find $SNAPSHOTS/openbricks/geexbox-xbmc-*/* -mtime +30 -delete
find $SNAPSHOTS/data/openbricks/geexbox-xbmc-*/* -mtime +30 -delete
#sendsnapshot
#sendsnapshotlink

# build configs
for conffile in $REPO/config/defconfigs/geexbox-xbmc-*.conf; do
  cd $BUILD
  NAME=`basename $conffile .conf`
  mkdir -p $LOGS/$REPONAME
  BUILDLOG="$LOGS/$REPONAME/$NAME.$DATE.log"
  log "Building $NAME"
  if [ ! -d "$NAME" ]; then
    log "Cloning $NAME"
    rm -f $STAMPS/$NAME
    hg clone $REPO $NAME > $BUILDLOG 
    ln -s $SOURCES $NAME/sources
    ln -s $STAMPSGET $NAME/.stamps
  fi

  if [ "$STAMPS/$REPONAME/$NAME" -nt $conffile ]; then
    log "Build $NAME is up to date"
    continue
  fi
  rm -f "$BUILDLOG"
  rm -f "$STAMPS/$REPONAME/$NAME"
  cd $NAME
  hg update -C >> $BUILDLOG 2>&1
  hg pull -u >> $BUILDLOG 2>&1
  ./scripts/kconfiginit >> $BUILDLOG 2>&1
  if grep -q 'CONFIG_OPT_TARGET_FLAT=y' config/defconfigs/$NAME.conf; then
    sed \
      -e 's:CONFIG_OPT_TARGET_FLAT=y:# CONFIG_OPT_TARGET_FLAT is not set:' \
      -e 's:# CONFIG_OPT_TARGET_TARBALL is not set:CONFIG_OPT_TARGET_TARBALL=y:' \
      -e 's:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:' \
      -e 's:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=9:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:'\
      < config/defconfigs/$NAME.conf \
      > `ls -d build/build.host/kconfig-frontends-*`/.config
  else
    cp -P config/defconfigs/$NAME.conf `ls -d build/build.host/kconfig-frontends-*`/.config
  fi
  make silentoldconfig >> $BUILDLOG 2>&1 || true
#  if [ $? -ne 0 ]; then
#    log "$NAME config failed"
#    rm -f "$STAMPS/$REPONAME/$NAME"
#    continue
#  fi
  make quickclean >> $BUILDLOG 2>&1
  if [ $? -ne 0 ]; then
    log "$NAME quickclean failed"
    mailfail clean
    rm -f "$STAMPS/$REPONAME/$NAME"
    continue
  fi
  rm -rf binaries
#  log "Fetching $NAME sources"
#  make get >> $BUILDLOG 2>&1
#  if [ $? -ne 0 ]; then
#    log "$NAME get failed"
#    mailfail get
#    rm -f "$STAMPS/$REPONAME/$NAME"
#    continue
#  fi
  log "Making $NAME"
  make >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "$NAME build successful"
    echo $DATE > "$STAMPS/$REPONAME/$NAME"
    mkdir -p "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME"
    cp -PR binaries/* "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
#    sendsnapshot
    ln -sf ../../data/$REPONAME/$NAME/$DATE $SNAPSHOTS/$REPONAME/$NAME/$DATE
#    sendsnapshotlink
# delete all *-dbg_* packages
    find $SNAPSHOTS/data/openbricks/geexbox-xbmc-*/* -name *-dbg_* -delete
    make quickclean
    log "Archiving $NAME log"
    lbzip2 -9 $BUILDLOG
  else
    log "Archiving $NAME log"
    lbzip2 -9 $BUILDLOG
    log "$NAME build failed"
    mailfail build
    rm -f "$STAMPS/$REPONAME/$NAME"
  fi
done

#log "Rsyncing snapshots to fry"
#rsync --archive --delete $SNAPSHOTS/* buildbot@fry.geexbox.org:/data/snapshots >> $BUILDLOG 2>&1
#if [ $? -eq 0 ]; then
#  log "rsync successful"
#else
#  log "rsync failed"
#fi
rm -f $STAMPS/lock
log "Quitting"
